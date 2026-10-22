//
//  BaseMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/21.
//

import Accelerate
import FoundationModels
import NaturalLanguage

/// The base memory store logic that other SDK-provided stores will be wrapping.
/// Matching logic: normalized-text match and cosine similarity.
class BaseMemoryStore {

    private var addedMemories: [MemoryEntry] = []

    /// Return an added memory as a search result only if the cosine similarity is larger than or equal to `similarityThreshold`,
    /// aka: there is enough similarity to the query.
    private let searchConfiguration: MemorySearchConfiguration

    /// Add a memory as a new entry only if the cosine similarity to every existing entry is smaller than `addThresholdSimilarity`,
    /// aka: there is enough distinction to the existing entries.
    ///
    /// - Similarity = 1: The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Similarity > 0: The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Similarity = 0: The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Similarity < 0: The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Similarity = -1: The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// However,`NaturalLanguage` embedding seems to weight more on repetitive phrases and usually result in a lower similarity than expected.
    private let addThresholdSimilarity: Double?

    /// A memory will be removed if its similarity to the new entry is smaller than `removeThresholdSimilarity`,
    /// aka: they point in the (nearly) opposite direction.
    private let removeThresholdSimilarity: Double?

    private let maxUnusedDays: Int?

    private let exactMatchSimilarity: Double = 1.0

    init(
        storeConfiguration: MemoryStoreConfiguration,
        existingMemories: [MemoryEntry]
    ) {
        self.addedMemories = existingMemories
        self.searchConfiguration = storeConfiguration.searchConfiguration
        self.addThresholdSimilarity = storeConfiguration.addThresholdSimilarity
        self.removeThresholdSimilarity =
            storeConfiguration.removeThresholdSimilarity
        self.maxUnusedDays = storeConfiguration.maxUnusedDays

        self.removeUnused()
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
        /// Calculating similarity to existing entries.
        let existingSimilarities = calculateSimilarities(
            base: self.addedMemories,
            queryEmbedding: newEmbedding
        )

        /// remove ones that are pointing in the opposite direction.
        if let removeThresholdSimilarity {
            let oppositeMemories = existingSimilarities.filter({
                $0.1 < removeThresholdSimilarity
            }).map(\.0)
            self.deleteMemories(oppositeMemories.map(\.id))
        }

        /// similar entries exist. return.
        if let addThresholdSimilarity,
            existingSimilarities.contains(where: {
                $0.1 >= addThresholdSimilarity
            })
        {
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
        ).map({ ($0, exactMatchSimilarity) })

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

        let similarities = calculateSimilarities(
            base: base,
            queryEmbedding: queryEmbedding
        )

        let similarMemories = applySearchConfig(
            to: similarities,
            categories: searchQuery.categories
        )

        return prepareForSearchResult(
            for: exactMatch + similarMemories
        )
    }

    func deleteMemories(_ memories: [MemoryEntry.ID]) {
        self.addedMemories.removeAll(where: { memories.contains($0.id) })
    }

    private func removeUnused() {
        guard let maxUnusedDays else { return }
        let now = Date()
        let threshold = Double(maxUnusedDays) * 60 * 60 * 24
        let memories = addedMemories.filter({
            let lastUsed = $0.lastUsed ?? $0.createdAt
            let distance = lastUsed.distance(to: now)
            return distance < threshold
        })
        self.addedMemories = memories
    }

    /// results: - an array of category-filtered memories, cosine similarity
    private func applySearchConfig(
        to results: [(MemoryEntry, Double)],
        categories: [Category]
    )
        -> [(MemoryEntry, Double)]
    {
        var final = results.sorted {
            $0.1 > $1.1
        }

        if let similarityThreshold = searchConfiguration.similarityThreshold {
            final = final.filter({
                if $0.1 >= similarityThreshold {
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
        similarity: Double?
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
            cosineSimilarity: similarity
        )
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

    // MARK: - Embedding
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

    // MARK: - cosine similarity
    private func calculateSimilarities(
        base: [MemoryEntry],
        queryEmbedding: [Double]?
    )
        -> [(MemoryEntry, Double)]
    {
        guard let queryEmbedding else { return [] }

        var similarities: [(MemoryEntry, Double)] = []
        base.forEach {
            if let similarity = calculateSimilarity(
                $0.embeddings,
                b: queryEmbedding
            ) {
                similarities.append(($0, similarity))
            }
        }
        return similarities
    }

    private func calculateSimilarity(_ a: [Double]?, b: [Double]?) -> Double? {
        guard let a, let b else { return nil }
        return calculateCosineSimilarity(a, b)
    }

    /// Calculate cosine similarity between two vector
    ///
    /// Returning: cosine similarity ranges between -1 and 1.
    ///
    /// - Similarity = 1: The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Similarity > 0: The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Similarity = 0: The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Similarity < 0: The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Similarity = -1: The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// Why not using `NLEmbedding.distance`
    /// we don't want to calculate the vector for both the stored memory and the query for every single similarity calculation.
    private func calculateCosineSimilarity(_ a: [Double], _ b: [Double])
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
        return max(
            -1.0,
            min(1.0, dotProduct / (magnitudeA * magnitudeB))
        )
    }
}
