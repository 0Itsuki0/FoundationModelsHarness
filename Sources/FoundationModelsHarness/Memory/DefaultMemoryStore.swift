//
//  DefaultMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/21.
//

//
//  backup.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/20.
//

import Accelerate
import FoundationModels
import NaturalLanguage
import SwiftUI

/// Calculate cosine distance between two vector
/// (mirroring `NLEmbedding.distance`'s calculation which is different from the standard textbook formula)
///
/// Returning: cosine distance ranges between 0 and 2.
///
/// - Distance = 0 (Similarity = 1): The vectors point in the exact same direction. They are perfectly identical in orientation.
/// - Distance < 1 (Similarity > 0): The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
/// - Distance = 1 (Similarity = 0): The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
/// - Distance > 1 (Similarity < 0): The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
/// - Distance = 2 (Similarity = -1): The vectors point in the exact opposite direction (a 180-degree angle).
///
/// Why not using `NLEmbedding.distance`
/// we don't want to calculate the vector for both the stored memory and the query for every single distance calculation.
func calculateCosineDistance(_ a: [Double], _ b: [Double]) -> Double? {
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

/// An entry per fact: { category, fact, timestamp, embeddings}
actor InMemoryMemoryStore {

    @Generable(
        description: """
            Categories for agent long-term memory:
            About the user
            - identity: name, role, timezone, language
            - preferences: style, formatting, tools, tone
            - goals: what they're working toward
            - constraints: things to avoid, hard rules
            - feedback: corrections given to the agent

            About the work
            - project: architecture, stack, key files, status
            - conventions: code style, naming, team norms
            - decisions: choices made and why
            - procedures: how to do recurring tasks (deploy, release, test)
            - issues: known bugs, gotchas, workarounds

            About the world
            - people: teammates, contacts, who owns what
            - references: URLs, docs, dashboards, tickets
            - facts: general knowledge that doesn't fit elsewhere

            About time
            - events: things that happened, with dates
            - tasks: open to-dos and follow-ups
            """
    )
    enum Category: String, Codable {
        /// About the user
        case identity
        case preferences
        case goals
        case constraints
        case feedback

        ///About the work
        case project
        case conventions
        case decisions
        case procedures
        case issues

        /// About the world
        case people
        case references
        case facts

        /// About time
        case events
        case tasks
    }

    @Generable()
    struct MemoryEntryPartial {
        @Guide(
            description: """
                Categories for agent long-term memory.
                """
        )
        var category: Category

        @Guide(
            description: """
                The fact to write to agent long-term memory in English.
                Rewrite first-person statements as standalone facts
                about the user, replacing "I", "my", and "me" with
                appropriate third-person references.

                Example:
                "My favorite Pokémon is Pikachu."
                -> "The user's favorite Pokémon is Pikachu."
                """
        )
        var fact: String
    }
    @Generable()
    struct MemorySearchQuery {
        @Guide(
            description: """
                Categories for agent long-term memory.
                Select the categories that best matches the information
                requested by the user.
                """,
            .minimumCount(1),
            .maximumCount(2)
        )
        var categories: [Category]

        @Guide(
            description: """
                The fact to retrieve from agent long-term memory in English.
                Express the specific information requested, preserving
                the relationship and attributes in the original question.

                Example:
                "What's my best friend's name?"
                -> "The identity of the user's best friend."

                Do not reduce relationship-specific questions to
                generic searches for a person, name, or topic.
                """
        )
        var query: String
    }

    @Generable()
    struct MemorySearchResult {
        @Guide(
            description: """
                Categories for agent long-term memory.
                """
        )
        var category: Category

        @Guide(
            description: """
                The fact retrieved from agent long-term memory.
                Treat this as retrieved evidence, not necessarily
                an answer to the user's question. Only use it to
                answer the question when its content supports the
                specific information or relationship requested.
                Do not infer unstated relationships.
                """
        )
        var fact: String

        @Guide(
            description: """
                The cosine distance between the query and retrieved
                fact, if available.

                - Distance = 0: Cosine similarity = 1; identical
                  embedding direction.
                - Distance < 1: Positive cosine similarity.
                - Distance = 1: Cosine similarity = 0; orthogonal
                  embedding directions.
                - Distance > 1: Negative cosine similarity.
                - Distance = 2: Cosine similarity = -1; opposite
                  embedding directions.

                Cosine distance measures semantic similarity, not
                whether the fact logically supports the answer.
                A low distance does not establish a relationship
                absent from the fact. A high distance indicates
                weaker or negative cosine similarity, not definitive
                proof of irrelevance. Do not use distance alone to
                determine whether a fact answers the question.
                """
        )
        var cosineDistance: Double?
    }
    struct MemoryEntry: Codable, Identifiable, CustomStringConvertible {
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

    private var addedMemories: [MemoryEntry] = []

    /// Add a memory as a new entry only if the cosine distance is larger than `addThresholdDistance`,
    /// aka: there is enough distinction to the existing entries.
    ///
    /// - Distance = 0 (Similarity = 1): The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Distance < 1 (Similarity > 0): The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Distance = 1 (Similarity = 0): The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Distance > 1 (Similarity < 0): The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Distance = 2 (Similarity = -1): The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a larger distance than expected.
    /// Ex:
    private let addThresholdDistance: Double = 1.1

    /// Return an added memory as a search result only if the cosine distance is less than or equal to `searchThresholdDistance`,
    /// aka: there is enough similarity to the query.
    private let searchCutOff: SearchConfiguration = .init(
        distanceThreshold: 1.2
    )

    /// A memory will be removed if its distance to the new entry is larger than `removeThresholdDistance`,
    /// aka: they point in the opposite direction
    private let removeThresholdDistance: Double = 1.8

    private let exactMatchDistance: Double = 0.0

    private let maxUnusedDays: Int = 30

    struct SearchConfiguration {
        /// whether to keep same category entry even when they are beyond the distance threshold
        var keepSameCategory: Bool = true

        /// Recommended value if using Apple's NaturalLanguage: 1.0 ~ 1.2.
        /// 1.0 itself means orthogonal textbook-definition wise,
        /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a larger distance than expected.
        var distanceThreshold: Double?
        var topK: Int?
    }

    init(memories: [MemoryEntry]) {
        self.addedMemories = memories
        Task {
            await self.cleanupUnusedMemories(memories)
        }
    }

    private func cleanupUnusedMemories(_ memories: [MemoryEntry]) {
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
    func addMemory(_ memory: MemoryEntryPartial) {
        let query = memory.fact
        let newEmbedding = calculateEmbedding(query)
        guard let newEmbedding else {
            if findExactMatch(base: self.addedMemories, to: query) != nil {
                return
            }
            self.addedMemories.append(
                .init(category: memory.category, fact: query, embeddings: nil)
            )
            return
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

        self.removeOppositeMemories(oppositeMemories)

        /// similar entries exist. return.
        if existingDistances.contains(where: {
            $0.1 <= self.addThresholdDistance
        }) {
            return
        }
        self.addedMemories.append(
            .init(
                category: memory.category,
                fact: query,
                embeddings: newEmbedding
            )
        )
    }

    func searchMemory(_ searchQuery: MemorySearchQuery) -> [MemorySearchResult]
    {
        let query = searchQuery.query
        let queryEmbedding = calculateEmbedding(query)
        let exactMatch: [(MemoryEntry, Double?)] =
            findExactMatch(
                base: self.addedMemories,
                to: query
            ).flatMap({ ($0, exactMatchDistance) }).flatMap({ [$0] }) ?? []

        let sameCategoryMatch: [(MemoryEntry, Double?)] = self.addedMemories
            .filter({
                searchQuery.categories.contains($0.category)
            }).map({ ($0, nil) })

        guard let queryEmbedding else {
            return prepareForSearchResult(
                for: exactMatch + sameCategoryMatch
            )
        }

        let existingDistances = calculateDistances(
            base: self.addedMemories,
            queryEmbedding: queryEmbedding
        )
        let memories = existingDistances.compactMap {
            (id, distance) -> (MemoryEntry, Double)? in
            if let entry = self.addedMemories.first(where: { $0.id == id }) {
                return (entry, distance)
            }
            return nil
        }

        var similarMemories = applySearchCutOff(
            to: memories,
            categories: searchQuery.categories
        )

        similarMemories.removeAll(where: {
            exactMatch.map(\.0.id).contains($0.0.id)
        })

        return prepareForSearchResult(
            for: similarMemories + exactMatch
        )
    }

    private func applySearchCutOff(
        to results: [(MemoryEntry, Double)],
        categories: [Category]
    )
        -> [(MemoryEntry, Double)]
    {
        var final = results.sorted {
            $0.1 < $1.1
        }

        if let distanceThreshold = searchCutOff.distanceThreshold {
            final = final.filter({
                if $0.1 <= distanceThreshold {
                    return true
                }
                if searchCutOff.keepSameCategory {
                    return categories.contains($0.0.category)
                }
                return false
            })
        }

        if let topK = searchCutOff.topK {
            final = Array(final.prefix(topK))
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
            category: memory.category,
            fact: memory.fact,
            cosineDistance: distance
        )
    }

    private func removeOppositeMemories(_ memories: [MemoryEntry.ID]) {
        print(#function, memories)
        self.addedMemories.removeAll(where: { memories.contains($0.id) })
    }

    private func findExactMatch(base: [MemoryEntry], to query: String)
        -> MemoryEntry?
    {
        let normalizedQuery = normalize(query)
        return base.first(where: {
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

    func calculateDistances(base: [MemoryEntry], queryEmbedding: [Double]?)
        -> [(MemoryEntry.ID, Double)]
    {
        guard let queryEmbedding else { return [] }

        var distances: [(MemoryEntry.ID, Double)] = []
        base.forEach {
            if let distance = calculateDistance(
                $0.embeddings,
                b: queryEmbedding
            ) {
                distances.append(($0.id, distance))
            }
        }
        return distances
    }

    func calculateDistance(_ a: [Double]?, b: [Double]?) -> Double? {
        guard let a, let b else { return nil }
        return calculateCosineDistance(a, b)
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
    func getNLEmbeddingInstance() -> NLEmbedding? {
        return NLEmbedding.sentenceEmbedding(for: .english)
    }

    func calculateEmbedding(_ query: String) -> [Double]? {
        return getNLEmbeddingInstance()?.vector(for: query)
    }
}

struct AddMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    let name = "add_memory"
    let description = """
        Save information to long-term memory for recall in future conversations.

        Convert the user's statements into concise, standalone facts written from the user's perspective in the third person. Never store first-person phrasing such as "I", "my", or "we" verbatim. Preserve the original meaning without adding assumptions.

        Examples:
        - Input: "My favorite Pokémon is Pikachu. This is important."
        Fact: "The user's favorite Pokémon is Pikachu."
        - Input: "I prefer SwiftUI over UIKit."
        Fact: "The user prefers SwiftUI over UIKit."
        - Input: "Our project uses Supabase."
        Fact: "The user's project uses Supabase."

        Store durable preferences, personal facts, decisions, and ongoing project context that may be useful in future conversations. Keep each fact concise and specific.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output)
    {
        self.call = call
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
    }
}

struct SearchMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    let name = "search_memory"
    let description = """
        Search long-term memory for facts, preferences, and context from previous conversations.

        Interpret search queries from the user's perspective and match them against stored facts, including facts written in the third person. Resolve references such as "I", "my", "we", and "our" to the relevant user or project context when searching.

        Search for the underlying meaning rather than requiring exact wording. Use relevant keywords, synonyms, and contextual clues to find information even when the query differs from how the fact was originally stored.

        When returning results, provide the relevant stored facts accurately. When using retrieved facts to answer the user's original question, **speak directly to the user in natural language**. Treat phrases such as "the user" as internal memory notation, not wording to repeat in conversation. Convert third-person references into the appropriate first- or second-person phrasing when answering.

        When interpreting search results, distinguish between a fact that mentions a relevant entity and a fact that actually answers the question. A shared name, keyword, or topic does not establish a relationship that is absent from the retrieved fact.

        For example:
        - Question: "Where do I live?"
        - Query: "user's location"
        - Retrieved fact: "The user is an iOS developer based in Tokyo, timezone JST (UTC+9)."
        - Answer: "You live in Tokyo."

        - Question: "What's my best friend's name?"
        - Retrieved fact: "Ken owns the backend API that the iOS app talks to."
        - Correct interpretation: The retrieved fact identifies Ken as the backend API owner, but provides no information about whether Ken is the user's best friend.
        - Correct response: "I couldn't find your best friend's name in memory."

        Use this tool when you need to recall user preferences, personal facts, previous decisions, ongoing project details, or information discussed in earlier conversations. Return relevant existing information without inventing facts or treating missing results as evidence that something never happened.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output)
    {
        self.call = call
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
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
