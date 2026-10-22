//
//  backup.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/20.
//

import Accelerate
import FoundationModels
import FoundationModelsHarness
import NaturalLanguage
import SwiftUI
//
//private let testEntries: [InMemoryMemoryStore.MemoryEntry] = {
//    let facts: [(InMemoryMemoryStore.Category, String)] = [
//        /// About the user
//        (.identity, "The user's name is Itsuki."),
//        (
//            .identity,
//            "The user is an iOS developer based in Tokyo, timezone JST (UTC+9)."
//        ),
//        (
//            .preferences,
//            "The user prefers concise answers without lengthy explanations."
//        ),
//        (
//            .constraints,
//            "Never commit or push to git without the user's explicit permission."
//        ),
//        (.constraints, "Do not add third-party dependencies to the project."),
//        /// About the work
//        (
//            .project,
//            "FoundationModelsHarness is a Swift package providing agents, tools, memory and goal plugins for Foundation Models."
//        ),
//        (
//            .project,
//            "Long-term memory uses NLEmbedding sentence embeddings with cosine distance for similarity search."
//        ),
//
//        /// About the world
//        (.people, "Ken owns the backend API that the iOS app talks to."),
//        /// About time
//        (
//            .tasks,
//            "On 2026-10-08 the user started the FoundationModelsHarness project."
//        ),
//        (
//            .tasks,
//            "On 2026-10-19 a tool delegation bug was fixed when a delegated tool is added or removed."
//        ),
//        (
//            .tasks,
//            "Add automatic clean up of memories that have not been used for 30 days."
//        ),
//    ]
//    return facts.map {
//        .init(
//            category: $0.0,
//            fact: $0.1,
//            embeddings: NLEmbedding.sentenceEmbedding(for: .english)?.vector(
//                for: $0.1
//            )
//        )
//    }
//}()

actor InMemoryMemoryStore {
    /// No `identity` related category as those are application logic instead of something to be saved as long-term memory
    @Generable(description: "Categories for long-term memory.")
    enum Category: Codable {
        /// About the user
        case preferences
        
        ///About the work
        case project
        
        /// About the world
        case people
        
        /// events
        case tasks
    }

    @Generable(description: "Fact to save to LLM's memory.")
    struct MemoryEntryPartial {
        @Guide(
            description: "Categories for the fact."
        )
        var category: Category

        @Guide(
            description: """
                Multi-word fact: who/to whom, on what. No sentence. No verb. In English.
                """
        )
        var fact: String
    }

    @Generable()
    enum AddMemoryResult {
        case success
        case failed(String)
    }

    @Generable()
    struct MemorySearchQuery {
        @Guide(
            description: """
                Categories for long-term memory.
                Select the categories that best matches the information needed.
                """,
            .minimumCount(1),
            .maximumCount(2)
        )
        var categories: [Category]

        @Guide(
            description: """
                Multi-word query: who/to whom, on what. No sentence. No verb. No Pronouns. In English.
                """
        )
        var query: String
    }

    @Generable()
    struct MemorySearchResult {
        var id: String

        @Guide(
            description: "Categories for long-term memory."
        )
        var category: Category

        @Guide(
            description: """
                The fact retrieved from long-term memory.
                Treat this as retrieved evidence, not necessarily an answer to the user's question.
                Only use it to answer the question when its content supports the specific information or relationship requested.
                Do not infer unstated relationships.
                """
        )
        var fact: String

        @Guide(
            description: """
                The cosine distance between the query and retrieved fact, if available.

                The lower it is, the better the match. 
                - 0 means the fact matches the query as well as the query matches itself.
                - 1 means they are unrelated
                - sqrt(2) means they are opposite facts. 

                Cosine distance measures semantic similarity, not whether the fact logically supports the answer.
                A low distance does not establish a relationship absent from the fact. 
                A high distance indicates weaker or negative cosine similarity, not definitive proof of irrelevance. Do not use distance alone to determine whether a fact answers the question.
                """
        )
        var cosineDistance: Double?
    }

    struct MemoryEntry: Identifiable, CustomStringConvertible {
        var id = UUID()

        var category: Category
        var fact: String
        var createdAt: Date = Date()
        /// for auto clean up if needed.
        var lastUsed: Date? = nil
        /// nil if failed. in this case, will only be matched based on category
        var embeddings: [Double]?

        init(
            category: Category,
            fact: String,
            embeddings: [Double]?
        ) {
            self.category = category
            self.fact = fact
            self.embeddings = embeddings
        }

        var description: String {
            """
            MemoryEntry (id: \(id): 
            - category: \(category)
            - fact: \(fact)
            - lastUsed: \(lastUsed?.formatted(), default: "(never used)")
            """
        }
    }

    struct SearchConfiguration {
        /// whether to use same category entry when there is no result returned after filtering with `distanceThreshold` and `topK`
        var useSameCategoryFallback: Bool = true

        /// Recommended value if using Apple's NaturalLanguage: 1.0 ~ 1.2.
        /// 1.0 itself means orthogonal textbook-definition wise,
        /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a larger distance than expected.
        var distanceThreshold: Double?

        /// Limit the search result to top K matches
        var topK: Int?
    }

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
    private let searchConfiguration: SearchConfiguration = .init(
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

    func searchMemory(_ searchQuery: MemorySearchQuery) -> [MemorySearchResult]
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

private let testingQuery: [String] = [
    /// paraphrases of stored facts (expected: close match)
    "What is the user's name?",
    "Where does the user live and what timezone are they in?",
    "Does the user like short or long responses?",
    "Which programming language does the user use?",
    "Am I allowed to push commits to git?",
    "Can I add an external library to the package?",
    "What is FoundationModelsHarness?",
    "How does memory search work?",
    "Why NLEmbedding instead of NLContextualEmbedding?",
    "How do I run the example?",
    "Is NLEmbedding thread safe?",
    "Who is responsible for the backend?",
    "Where are the Foundation Models docs?",
    "How large is the on-device model's context window?",
    "When did the project start?",
    "What bug was fixed recently?",
    "What are the open tasks?",

    /// opposites of stored facts (expected: large distance)
    "The user prefers long, detailed explanations.",
    "Feel free to commit and push to git anytime.",

    /// unrelated (expected: no match)
    "What's the weather like in Paris today?",
    "Recommend a good pasta recipe.",
]

//print(calculateCosineDistance(v1, b: v2))

//let store = InMemoryMemoryStore(memories: testEntries)
//let addTool = AddMemoryTool(call: { argument in
//    await store.addMemory(argument)
//    return true
//})
//let searchTool = SearchMemoryTool(call: { argument in
//    return await store.searchMemory(argument)
//})
//
//do {
//    let session = LanguageModelSession(
//        model: SystemLanguageModel(),
//        tools: [
//            addTool, searchTool,
//        ],
//        instructions: nil
//    )
//    for query in testingQuery {
//        print("-----")
//        let response = try await session.respond(to: query)
//        printHistory(session.transcript.history)
//        session.transcript.history.removeAll()
//    }
//    //    let _ = try await session.respond(
//    //        to: "My favorite pokemon is pikachu. this is important"
//    //    )
//    //    let _ = try await session.respond(
//    //        to: "My name is itsuki. this is important"
//    //    )
//    //    let _ = try await session.respond(
//    //        to: "what's my best friend's name?"
//    //    )
//    //    print(response.content)
//
//    //    let prompt = Prompt {
//    //        Attachment(imageURL: URL(filePath: "/Users/itsuki/Desktop/pikachu/pikachu.jpg"))
//    //        "What's in the image"
//    //    }
//    //    let segments = await segments(from: prompt)
//    //    session.transcript.history.append(.prompt(.init(segments: segments)))
//    //    let response = try await session.respond(to: "")
//    //    print(response.rawContent)
//
//} catch {
//    print(error)
//}

//if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
//    let sentence = "The user's name is Itsuki."
//
//
//    let distance = sentenceEmbedding.distance(between: sentence, and: "The user is named Itsuki.")
//    print(distance.description)
//}

//
//let agent = Agent(
//    tools: [
////        .init(tool: GreetingTool(), delegate: true)
//    ],
//    instruction: .init("You are a helpful assistant.")
//)
//agent.addTool(.init(tool: GreetingTool(), delegate: true))

//agent.addHook(
//    AfterToolCallEventHandler(callback: { event in
//        if event.attemptCount < 2 {
//            event.retry = true
//        } else {
//            event.toolResult = .failure(NSError(domain: "failed", code: 1))
//        }
//    })
//)

//agent.agentState["app"] = "Test"
//let result = await agent.respond(
//    to: "hello. greet itsuki",
//    invocationState: ["resume": true]
//)

//print("result", result)
////print("response: ", response.rawContent as Any)
//print("-----")
//await agent.respond(to: "how's going")

// testing stream
//await printStream(agent.streamResponse(to: "hello. greet itsuki.", invocationState: ["resume": true]))
//await printStream(
//    agent.streamResponse(to: "how's going?")
//)
//
//printHistory(agent.history)

//await toolDelegation()

//
