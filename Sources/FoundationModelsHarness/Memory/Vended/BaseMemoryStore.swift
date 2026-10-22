//
//  BaseMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/21.
//

import Accelerate
import FoundationModels
import NaturalLanguage

/// The base memory store logic that other SDK-provided store will be wrapping
actor BaseMemoryStore {


    private var addedMemories: [MemoryEntry] = []

    /// Add a memory as a new entry only if the cosine distance is larger than `addThresholdDistance`,
    /// aka: there is enough distinction to the existing entries.
    ///
    /// - Distance = 0 (Similarity = 1): The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Distance < 1 (Similarity > 0): The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Distance = 1 (Similarity = 0): The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Distance > 1 (Similarity < 0): The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Distance = sqrt(2) (Similarity = -1): The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// However,`NaturalLanguage` embedding seems to weight more on repetitive phrases and usually result in a larger distance than expected.
    private let addThresholdDistance: Double = 1.0

    /// Return an added memory as a search result only if the cosine distance is less than or equal to `searchThresholdDistance`,
    /// aka: there is enough similarity to the query.
    private let searchConfiguration: MemorySearchConfiguration = .init(
        distanceThreshold: 1.2
    )

    /// A memory will be removed if its distance to the new entry is larger than `removeThresholdDistance`,
    /// aka: they point in the opposite direction.
    /// Since we are taking sqrt to the textbook Cosine distance, the full-contradictory distance becomes sqrt(2), or 1.41421356237
    private let removeThresholdDistance: Double = 1.38

    private let exactMatchDistance: Double = 0.0

    private let maxUnusedDays: Int = 30

    init(memories: [MemoryEntry]) {
        self.addedMemories = memories
        Task {
            await self.removeUnused(memories)
        }
    }

    private func removeUnused(_ memories: [MemoryEntry]) {
        let now = Date()
        let threshold = Double(self.maxUnusedDays) * 60 * 60 * 24
        let memories = memories.filter({
            let lastUsed = $0.lastUsed ?? $0.createdAt
            let distance = lastUsed.distance(to: now)
            return distance < threshold
        })
        self.addedMemories = memories
    }

    /// add an entry to memory
    /// Always returning `success` because even when there is a similar memory already added, it is not necessarily a failure that the LLM needs to know
    func addMemory(_ memory: MemoryEntryPartial) -> AddMemoryResult {
        let query = memory.fact
        let newEmbedding = calculateEmbedding(query)
        guard let newEmbedding else {
            if !findExactMatch(base: self.addedMemories, to: query).isEmpty {
                return .success
            }
            self.addedMemories.append(
                .init(category: memory.category, fact: query, embeddings: nil)
            )
            return .success
        }
        /// Calculating distance to existing entries.
        let existingDistances = calculateDistances(
            base: self.addedMemories,
            queryEmbedding: newEmbedding
        )

        /// remove ones that are pointing in the opposite direction.
        let oppositeMemories = existingDistances.filter({
            $0.1 > self.removeThresholdDistance
        }).map(\.0)

        self.removeOppositeMemories(oppositeMemories.map(\.id))

        /// similar entries exist. return.
        if existingDistances.contains(where: {
            $0.1 <= self.addThresholdDistance
        }) {
            return .success
        }
        self.addedMemories.append(
            .init(
                category: memory.category,
                fact: query,
                embeddings: newEmbedding
            )
        )
        return .success
    }

    func searchMemory(_ searchQuery: MemorySearchInput) -> [MemorySearchResult]
    {
        let query = searchQuery.query
        let queryEmbedding = calculateEmbedding(query)
        let exactMatch: [(MemoryEntry, Double?)] = findExactMatch(
            base: self.addedMemories,
            to: query
        ).map({ ($0, exactMatchDistance) })

        var base =
            searchQuery.categories.isEmpty
            ? self.addedMemories
            : self.addedMemories.filter({
                searchQuery.categories.contains($0.category)
            })

        base.removeAll(where: {
            exactMatch.map(\.0.id).contains($0.id)
        })

        guard let queryEmbedding else {
            return prepareForSearchResult(
                for: exactMatch
                    + base.map({
                        ($0, nil)
                    })
            )
        }

        let distances = calculateDistances(
            base: base,
            queryEmbedding: queryEmbedding
        )

        let similarMemories = applySearchConfig(
            to: distances,
            categories: searchQuery.categories
        )

        return prepareForSearchResult(
            for: exactMatch + similarMemories
        )
    }

    /// results: - an array of category-filtered memories, cosine distance
    private func applySearchConfig(
        to results: [(MemoryEntry, Double)],
        categories: [Category]
    )
        -> [(MemoryEntry, Double)]
    {
        var final = results.sorted {
            $0.1 < $1.1
        }

        if let distanceThreshold = searchConfiguration.distanceThreshold {
            final = final.filter({
                if $0.1 <= distanceThreshold {
                    return true
                }
                return false
            })
        }
        if let topK = searchConfiguration.topK {
            final = Array(final.prefix(topK))
        }

        if final.isEmpty, searchConfiguration.useSameCategoryFallback {
            return results
        }

        return final
    }

    private func prepareForSearchResult(for memories: [(MemoryEntry, Double?)])
        -> [MemorySearchResult]
    {
        return memories.map(prepareForSearchResult)
    }

    private func prepareForSearchResult(
        for memory: MemoryEntry,
        distance: Double?
    )
        -> MemorySearchResult
    {
        if let firstIndex = self.addedMemories.firstIndex(where: {
            $0.id == memory.id
        }) {
            self.addedMemories[firstIndex].lastUsed = Date()
        }
        return MemorySearchResult(
            id: memory.id.uuidString,
            category: memory.category,
            fact: memory.fact,
            cosineDistance: distance
        )
    }

    private func removeOppositeMemories(_ memories: [MemoryEntry.ID]) {
        self.addedMemories.removeAll(where: { memories.contains($0.id) })
    }

    private func findExactMatch(base: [MemoryEntry], to query: String)
        -> [MemoryEntry]
    {
        let normalizedQuery = normalize(query)
        return base.filter({
            normalize($0.fact).contains(normalizedQuery)
        })
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacing(/[^\p{L}\p{N}_\s]/, with: "")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func calculateDistances(
        base: [MemoryEntry],
        queryEmbedding: [Double]?
    )
        -> [(MemoryEntry, Double)]
    {
        guard let queryEmbedding else { return [] }

        var distances: [(MemoryEntry, Double)] = []
        base.forEach {
            if let distance = calculateDistance(
                $0.embeddings,
                b: queryEmbedding
            ) {
                distances.append(($0, distance))
            }
        }
        return distances
    }

    private func calculateEmbedding(_ query: String) -> [Double]? {
        return getNLEmbeddingInstance()?.vector(for: query)
    }

    /// NOTE:
    /// 1.  A single NLEmbedding instance isn’t safe for concurrent use.
    /// Calling functions on one instance from multiple threads or tasks at the same time can crash your app.
    /// Serialize access to a shared instance, or give each thread or task its own instance.
    ///
    /// 2. Using `NLEmbedding` instead of `NLContextualEmbedding` because our task here is semantic similarity and using`NLEmbedding` is [what Apple recommends](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding).
    ///
    /// 3. Why always english:
    /// Memory added is generated by LM, memory retrieved is sent to LM. Therefore, we can just pick a language on the saving side.
    private func getNLEmbeddingInstance() -> NLEmbedding? {
        return NLEmbedding.sentenceEmbedding(for: .english)
    }

    private func calculateDistance(_ a: [Double]?, b: [Double]?) -> Double? {
        guard let a, let b else { return nil }
        return calculateCosineDistance(a, b)
    }

    /// Calculate cosine distance between two vector
    /// (mirroring `NLEmbedding.distance`'s calculation which is different from the standard textbook formula)
    ///
    /// Returning: cosine distance ranges between 0 and 2.
    ///
    /// - Distance = 0 (Similarity = 1): The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Distance < 1 (Similarity > 0): The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Distance = 1 (Similarity = 0): The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Distance > 1 (Similarity < 0): The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Distance = sqrt(2) (Similarity = -1): The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// Why not using `NLEmbedding.distance`
    /// we don't want to calculate the vector for both the stored memory and the query for every single distance calculation.
    private func calculateCosineDistance(_ a: [Double], _ b: [Double])
        -> Double?
    {
        guard a.count == b.count else {
            return nil
        }

        /// dot product
        let dotProduct = vDSP.dot(a, b)
        /// norm A
        let magnitudeA = sqrt(vDSP.sumOfSquares(a))
        /// norm B
        let magnitudeB = sqrt(vDSP.sumOfSquares(b))

        /// verification to prevent division-by-zero or floating drift
        if magnitudeA == 0.0 || magnitudeB == 0.0 {
            return nil
        }

        /// standard Cosine Similarity clamped to valid math boundaries [-1, 1]
        let cosineSimilarity = max(
            -1.0,
            min(1.0, dotProduct / (magnitudeA * magnitudeB))
        )

        ///Textbook Cosine Distance
        let standardCosineDistance = 1.0 - cosineSimilarity

        /// Apple NaturalLanguage Framework Transformation (Euclidean distance of unit vectors)
        /// For orthogonal vectors where similarity is 0, this yields sqrt(2) ≈ 1.4142
        return sqrt(2.0 * standardCosineDistance)
    }
}
