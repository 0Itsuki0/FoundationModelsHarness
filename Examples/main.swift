//
//  main.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import Accelerate
import FoundationModels
import FoundationModelsHarness
import GRDB
import NaturalLanguage
import SwiftUI

extension SQLiteMemoryStore {
    /// No `identity` related category as those are application logic instead of something to be saved as long-term memory
    @Generable(description: "Categories for long-term memory.")
    enum Category: String, Codable, DatabaseValueConvertible {
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

    @Generable(description: "Update an existing memory.")
    struct MemoryUpdate {
        @Guide(description: "Id of the existing memory.")
        var id: Int

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
                Categories to search for.
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
    struct MemorySearchResult: Codable, FetchableRecord, PersistableRecord {
        var id: Int

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
                The similarity score between the query and retrieved fact from 0 to 1, if available.
                The higher it is, the better the match. 1 means the fact matches the query as well as the query matches itself.

                The score measures word overlap, not whether the fact logically supports the answer.
                - A high score does not establish a relationship absent from the fact.
                - A low score indicates fewer shared words, not definitive proof of irrelevance.

                Do **not** use the score alone to determine whether a fact answers the question.
                """
        )
        var similarity: Double?
    }

    struct MemoryEntry: Codable, FetchableRecord, MutablePersistableRecord,
        Identifiable, CustomStringConvertible
    {
        static let databaseTableName: String = "memory"

        var id: Int64?
        var category: Category
        var fact: String
        var createdAt: Date = Date()
        var lastUsed: Date? = nil

        mutating func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }

        var description: String {
            """

            MemoryEntry (id: \(id, default: "(not assigned)")):
            - category: \(category)
            - fact: \(fact)
            - lastUsed: \(lastUsed?.formatted(), default: "(never used)")
            """
        }

    }

    struct SearchConfiguration {
        /// whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
        var useSameCategoryFallback: Bool = true

        /// Cut off value for the similarity (0 to 1): Anything at or above the threshold will be returned.
        /// Similarity: `rank(memory) / rank(query itself)`, clamped to 1. The higher it is, the better the match
        var similarityThreshold: Double?

        /// Limit the search result to top K matches
        var topK: Int?
    }
}

/// Virtual table `rank` column: different from cosine distance,
/// the value of it is *relative* to the FTS5Pattern created from the query.
/// Therefore, instead of a hard cutoff on the`rank` value itself, we
/// 1. insert the pending string (either query or the memory fact) into the table
/// 2. get the rank for the inserted item
/// 3. use this rank as as a standard (similarity score 1) and calculate the similarity score for other entries based on it.
///     - the similarity score for other items will always be from 0 to 1 because the negative the `rank`, the better the match, and the item itself is guaranteed to be the best match -> lowest `rank` value
actor SQLiteMemoryStore {
    private var migrator = DatabaseMigrator()

    private let dbPool: DatabasePool

    private let searchConfiguration = SearchConfiguration(topK: 10)
    private let addSimilarityThreshold: Double = 0.8

    private var updateTask: Task<Void, Error>?
    private var isUpdating: Bool = false

    private var pendingUpdates: Set<MemoryEntry.ID> = []

    private let memoryTableName: String = MemoryEntry.databaseTableName
    private let searchTableName: String =
        "\(MemoryEntry.databaseTableName)_search"

    /// Create an SQLite database
    ///
    /// - parameters:
    ///  - url: URL to the database file.
    /// - throws: A ``DatabaseError`` whenever an SQLite error occurs.
    init(url: URL = URL.applicationDirectory.appending(path: "memory.db"))
        throws
    {
        migrator.eraseDatabaseOnSchemaChange = true

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            self.dbPool = try DatabasePool(path: url.path)

            let tableName = memoryTableName
            let searchTableName = searchTableName

            migrator.registerMigration("create_memory_table") { db in
                // 1. Create the content table
                try db.create(table: tableName) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("category", .text).notNull()
                    t.column("fact", .text).notNull()
                    t.column("createdAt", .datetime).notNull()
                    t.column("lastUsed", .datetime)
                }

                try db.create(
                    virtualTable: searchTableName,
                    using: FTS5()
                ) {
                    t in
                    t.synchronize(withTable: tableName)
                    t.column("fact")
                    t.tokenizer = .unicode61()
                }
            }
            try migrator.migrate(dbPool)

            Task {
                do {
                    try await removeUnused()
                } catch {
                    print("Error removing unused memories: ", error)
                }
            }
        } catch (let error) {
            print(
                "Fail to set up local database: \(error.localizedDescription)"
            )
            throw error
        }
    }

    /// - topK: the best K matches
    /// - similarityThreshold: Anything at or above the threshold will be returned
    func searchMemory(_ searchQuery: MemorySearchQuery) async throws
        -> [MemorySearchResult]
    {
        let queryText: String = searchQuery.query
        let categories: [Category] = searchQuery.categories

        let searchPattern =
            queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : FTS5Pattern(matchingAnyTokenIn: queryText)

        let tableName = memoryTableName
        let searchTableName = searchTableName
        let topK = searchConfiguration.topK
        let similarityThreshold = searchConfiguration.similarityThreshold
        let useSameCategoryFallback = searchConfiguration
            .useSameCategoryFallback

        @Sendable func fetchMatchingCategories(_ db: Database) throws
            -> [MemorySearchResult]
        {
            var sql =
                "SELECT id, category, fact, NULL AS similarity FROM \(tableName)"
            var arguments = StatementArguments()

            if !categories.isEmpty {
                let placeholders = categories.map { _ in "?" }.joined(
                    separator: ", "
                )
                sql += "\nWHERE category IN (\(placeholders))"
                arguments += StatementArguments(categories)
            }

            return try MemorySearchResult.fetchAll(
                db,
                sql: sql,
                arguments: arguments
            )
        }

        /// A write, since the query is temporarily inserted to get its own rank as the reference for the similarity.
        let result = try await dbPool.writeWithoutTransaction { db in

            guard let searchPattern else {
                /// No valid pattern: query the content table with the category filter only.
                return try fetchMatchingCategories(db)
            }

            var result: [MemorySearchResult] = []

            try db.inTransaction {
                /// Category is irrelevant: the row is excluded from the results and rolled back.
                var queryEntry = MemoryEntry(
                    category: .people,
                    fact: queryText
                )
                try queryEntry.insert(db)

                // Score of the query against its own tokens: the reference for this query.
                guard let queryId = queryEntry.id,
                    let selfRank = try Double.fetchOne(
                        db,
                        sql: """
                            SELECT rank FROM \(searchTableName)
                            WHERE \(searchTableName) MATCH ? AND rowid = ?
                            """,
                        arguments: [searchPattern, queryId]
                    ),
                    selfRank < 0
                else {
                    return .rollback
                }

                // MATCH must run against the FTS table, so join it with the content table.
                /// Both ranks are negative, so the ratio is positive. Clamp to 1 since a shorter row can outscore self.
                var sql = """
                    SELECT \(tableName).id, \(tableName).category, \(tableName).fact, MIN(\(searchTableName).rank / ?, 1.0) AS similarity
                    FROM \(tableName)
                    JOIN \(searchTableName)
                        ON \(searchTableName).rowid = \(tableName).id
                        AND \(searchTableName) MATCH ?
                    """
                var arguments: StatementArguments = [selfRank, searchPattern]
                var conditions: [String] = ["\(tableName).id != ?"]
                arguments += [queryId]

                if !categories.isEmpty {
                    let placeholders = categories.map { _ in "?" }.joined(
                        separator: ", "
                    )
                    conditions.append(
                        "\(tableName).category IN (\(placeholders))"
                    )
                    arguments += StatementArguments(categories)
                }

                if let similarityThreshold {
                    /// rank / selfRank >= threshold  <=>  rank <= threshold * selfRank, since selfRank is negative.
                    conditions.append("\(searchTableName).rank <= ?")
                    arguments += [similarityThreshold * selfRank]
                }

                sql += "\nWHERE " + conditions.joined(separator: " AND ")

                sql += "\nORDER BY \(searchTableName).rank"

                if let topK {
                    sql += "\nLIMIT ?"
                    arguments += [topK]
                }

                result = try MemorySearchResult.fetchAll(
                    db,
                    sql: sql,
                    arguments: arguments
                )

                return .rollback
            }

            /// After the rollback, so the temporary query row is not included.
            if result.isEmpty, useSameCategoryFallback {
                return try fetchMatchingCategories(db)
            }

            return result
        }

        self.updateLastUsed(result.map(\.id).map(Int64.init))

        return result
    }

    private func updateLastUsed(_ memoryIds: [MemoryEntry.ID]) {
        memoryIds.forEach { self.pendingUpdates.insert($0) }
        guard !self.isUpdating else { return }
        self.isUpdating = true
        updateTask = Task {
            try await self.updateLastUsed()
        }
    }

    private func updateLastUsed() async throws {
        while true {
            defer {
                self.isUpdating = false
            }
            let ids = pendingUpdates
            self.pendingUpdates.removeAll()
            guard !ids.isEmpty else { return }
            try await dbPool.write { db in
                _ =
                    try MemoryEntry
                    .filter(keys: ids)
                    .updateAll(db, Column("lastUsed").set(to: Date()))
            }
        }
    }

    func addMemory(_ memory: MemoryEntryPartial) async throws -> AddMemoryResult
    {
        return try await self.addMemories([memory])
    }

    func addMemories(_ memories: [MemoryEntryPartial]) async throws
        -> AddMemoryResult
    {
        return try await addMemoriesWithSimilarityCheck(
            memories,
            similarityThreshold: self.addSimilarityThreshold
        )
    }

    /// - similarityThreshold: `rank(existing) / rank(self)`, clamped to 1.
    /// At or above the threshold, the inserted memory is considered a duplicate and removed.
    func addMemoriesWithSimilarityCheck(
        _ memories: [MemoryEntryPartial],
        similarityThreshold: Double
    ) async throws -> AddMemoryResult {
        let memories: [MemoryEntry] = memories.map {
            MemoryEntry(category: $0.category, fact: $0.fact)
        }

        let searchTableName = "\(MemoryEntry.databaseTableName)_search"

        try await dbPool.write { [memories] db in
            for var memory in memories {
                try memory.insert(db)
                guard let id = memory.id,
                    let searchPattern = FTS5Pattern(
                        matchingAnyTokenIn: memory.fact
                    )
                else { continue }

                // Score of the inserted memory against its own tokens: the reference for this query.
                let selfRank = try Double.fetchOne(
                    db,
                    sql: """
                        SELECT rank FROM \(searchTableName)
                        WHERE \(searchTableName) MATCH ? AND rowid = ?
                        """,
                    arguments: [searchPattern, id]
                )

                // Best match among the existing memories.
                let bestRank = try Double.fetchOne(
                    db,
                    sql: """
                        SELECT rank FROM \(searchTableName)
                        WHERE \(searchTableName) MATCH ? AND rowid != ?
                        ORDER BY rank
                        LIMIT 1
                        """,
                    arguments: [searchPattern, id]
                )

                guard let selfRank, let bestRank, selfRank < 0 else { continue }

                /// Both ranks are negative, so the ratio is positive. Clamp to 1 since a shorter row can outscore self.
                let similarity = min(bestRank / selfRank, 1)

                /// there is an existing entry with similarity score larger than the threshold
                /// aka: a close match between the one trying to insert and some memories that is already added,
                /// delete the one inserted.
                if similarity >= similarityThreshold {
                    _ = try memory.delete(db)
                }
            }
        }

        return .success
    }

    func removeMemories(_ ids: [MemoryEntry.ID]) async throws {
        let ids = ids.compactMap { $0 }
        guard !ids.isEmpty else { return }

        try await dbPool.write { db in
            _ = try MemoryEntry.deleteAll(db, keys: ids)
        }
    }

    func removeUnused(maxUnusedDay: Int = 30) async throws {
        let cutoff = Date().addingTimeInterval(-30 * 60 * 60 * 24)

        try await dbPool.write { db in
            /// Never-used memories fall back to their creation date.
            _ =
                try MemoryEntry
                .filter(
                    (Column("lastUsed") ?? Column("createdAt")) < cutoff
                )
                .deleteAll(db)
        }
    }

    func allMemories() async throws -> [MemoryEntry] {
        return try await dbPool.read { db in
            return try MemoryEntry.fetchAll(db)
        }
    }
}

private let testEntries: [SQLiteMemoryStore.MemoryEntryPartial] = {
    let facts: [(SQLiteMemoryStore.Category, String)] = [
        /// About the user
        (
            .preferences,
            "The user prefers concise answers without lengthy explanations."
        ),
        (
            .preferences,
            "The user's favorite pokemon is pikachu."
        ),
        (
            .tasks,
            "The user wants to build an on-device agent harness on top of Apple Foundation Models."
        ),
        (
            .preferences,
            "Never commit or push to git without the user's explicit permission."
        ),
        (.preferences, "Do not add third-party dependencies to the project."),
        (
            .preferences,
            "The user said to only do exactly what is asked and not change unrelated code."
        ),

        /// About the work
        (
            .project,
            "FoundationModelsHarness is a Swift package providing agents, tools, memory and goal plugins for Foundation Models."
        ),
        (
            .project,
            "Long-term memory uses NLEmbedding sentence embeddings with cosine distance for similarity search."
        ),
        (
            .preferences,
            "Types use UpperCamelCase and functions use lowerCamelCase following Swift API design guidelines."
        ),
        (
            .preferences,
            "NLEmbedding was chosen over NLContextualEmbedding because the task is semantic similarity."
        ),
        /// About the world
        (.people, "Ken owns the backend API that the iOS app talks to."),
        (
            .people,
            "Foundation Models documentation: https://developer.apple.com/documentation/foundationmodels"
        ),
        /// About time
        (
            .tasks,
            "On 2026-10-08 the user started the FoundationModelsHarness project."
        ),
        (
            .tasks,
            "On 2026-10-19 a tool delegation bug was fixed when a delegated tool is added or removed."
        ),
        (
            .tasks,
            "Add automatic clean up of memories that have not been used for 30 days."
        ),
    ]
    return facts.map {
        .init(
            category: $0.0,
            fact: $0.1,
        )
    }
}()

struct AddMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    var name = "add_llm_memory"
    var description = """
        Save information to **Assistant's** long-term memory for recall in future conversations.
        - Save multi-word, concise, self-contained fact that preserves its original meaning and important relationships. NEVER Sentence.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(
        call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil
    ) {
        self.call = call

        if let nameOverride { self.name = nameOverride }
        if let descriptionOverride { self.description = descriptionOverride }
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
    }
}

struct SearchMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    var name = "search_user_info"
    var description = """
        Look up user-related information such as preferences, rules, relationships.
        - Search with multi-word query. NEVER Sentence.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(
        call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil
    ) {
        self.call = call

        if let nameOverride { self.name = nameOverride }
        if let descriptionOverride { self.description = descriptionOverride }
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
    }
}

private let testingQuery: [String] = [
    /// paraphrases of stored facts (expected: close match)
    "What is my name?",
    "Where does the user live and what timezone are they in?",
    "Does the user like short or long responses?",
    "Which programming language does the user use?",
    "Am I allowed to push commits to git?",
    "Can I add an external library to the package?",
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
    "Feel free to commit and push to git anytime.",
    "I really like pikachu! Super important!",

    /// unrelated (expected: no match)
    "What's the weather like in Paris today?",
    "Recommend a good pasta recipe.",
]

let url = URL.temporaryDirectory.appending(path: "memory.db")
try? FileManager.default.removeItem(at: url)
let store = try SQLiteMemoryStore(url: url)
let _ = try await store.addMemories(testEntries)
//let results = try await store.searchMemory(
//    .init(categories: [.identity], query: "user's name")
//)
//let store = InMemoryMemoryStore()

//print(results)
//try await Task.sleep(for: .milliseconds(300))
//print(try await store.allMemories().filter({ $0.category == .identity }))

//print(calculateCosineDistance(v1, b: v2))

//let store = InMemoryMemoryStore(memories: testEntries)
let addTool = AddMemoryTool(call: { argument in
    return try await store.addMemory(argument)
})
let searchTool = SearchMemoryTool(call: { argument in
    return try await store.searchMemory(argument)
})

//do {
//    let session = LanguageModelSession(
//        model: SystemLanguageModel(),
//        tools: [
//            addTool,
//            searchTool,
//        ],
//        instructions: Instructions {
//            """
//            Search for information about the user (\(searchTool.name)) when your answer depends on their
//            preferences, decisions, or circumstances.
//            Save (\(addTool.name)) lasting facts about the user as short self-contained statements.
//            """
//        }
//    )
//    for query in testingQuery {
//        let _ = try await session.respond(to: query)
//        printHistory(session.transcript.history)
//        session.transcript.history.removeAll()
//    }
//} catch {
//    print(error)
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

@Generable()
struct ExtractionResult {
    @Guide(description: "Facts to save to assistant's memory.")
    let add: [SQLiteMemoryStore.MemoryEntryPartial]

    @Guide(
        description:
            "Ids of the wrong facts that needs to be removed from assistant's memory."
    )
    let remove: [Int]
}

extension Array where Element == Transcript.Segment {
    var rawContent: String {
        return self.compactMap { segment -> String? in
            switch segment {
            case .text(let text):
                text.content.isEmpty ? nil : text.content
            case .structure(let structure):
                structure.content.jsonString
            case .attachment(_):
                nil
            @unknown default:
                nil
            }
        }.joined(separator: "\n")
    }

}

let extractor = LanguageModelExtractor(
    schema: ExtractionResult.generationSchema,
    buildPrompt: { entries in
        let string: String = entries.compactMap { message in
            switch message {
            case .prompt(let prompt):
                return "User: \(prompt.segments.rawContent)"
            case .response(let response):
                return "Assistant: \(response.segments.rawContent)"
            case .toolCalls(let calls):
                let getMemoryTools = calls.filter({
                    $0.toolName == searchTool.name
                })
                guard !getMemoryTools.isEmpty else {
                    return nil
                }
                return
                    "Tool Use (Get Memory): \(getMemoryTools.map(\.arguments)) "

            case .toolOutput(let output):
                guard output.toolName == searchTool.name else {
                    return nil
                }
                return "Tool Result: \(output.segments.rawContent)"
            default:
                return nil
            }
        }
        .joined(separator: "\n")

        return Prompt(string)
    }
)

do {
    let session = LanguageModelSession(
        model: SystemLanguageModel(),
        tools: [
            //            addTool,
            searchTool
        ],
        instructions: Instructions {
            """
            User's prompt that you need to respond to is surrounded by the `<user>` tag.
            Additional instructions that you need to follow is surrounded by the `<system>` tag.

            Look up information about the user using the [\(searchTool.name)] tool **whenever** knowing their preferences, works, tasks, or relationships *COULD possibly* make you better assistant them. 
            - Use the tool **proactively**. Do NOT wait for the user to prompt you explicitly to use it.  
            - Only use it as a reference. It is not guaranteed to be correct. It can be out-of-date. Never question what the user says.
            - Always answer in natural tone. 
            - If there is no results, answer normally. 
            - Never inform the user about the search result.
            """
        }
    )

    let _ = try await session.respond(
        to: """
                <user>Hey!</user> 
                <system>Use the [\(searchTool.name)] tool to look up user-related information **proactively**.</system>
            """
    )

    let _ = try await session.respond(
        to: """
                <user>Let's talk more about my favorite pokemon!</user> 
                <system>Use the [\(searchTool.name)] tool to look up user-related information **proactively**.</system>
            """
    )

    //    let _ = try await session.respond(
    //        to: """
    //                <user>why no look up what it is before you give shit?</user>
    //                <system>[\(searchTool.name)] tool available for user-related information look up. Use the tool **proactively**.</system>
    //            """
    //    )
    //    let _ = try await session.respond(to: "We have just talked about it. Why are you not looking it up. You don't even remember what it is? I am asking you why you are not searching fuck shit. YOu have the fucking tool on what it is. answer my question. why you are not looking it up.")
    //    let _ = try await session.respond(to: "You have the fucking tool to know my preference instead of asking what it is fuck you shit. why are you not using the \(searchTool.name) tool. Try it you dick. what tools do you have access to. print it out fuck.")

    printHistory(session.transcript.history)
    //    let content = try await extractor.extractMemory(
    //        from: Array(session.transcript.history)
    //    )
    //    print(content)

} catch {
    print(error)
}

//extension Transcript.Entry {
//    static func user(_ message: String) -> Transcript.Entry {
//        return .prompt(
//            Transcript.Prompt(segments: [.text(.init(content: message))])
//        )
//    }
//
//    static func assistant(_ message: String) -> Transcript.Entry {
//        return .response(
//            Transcript.Response(segments: [.text(.init(content: message))])
//        )
//    }
//}
//
//for scenario in scenarios {
//    let transcript: [Transcript.Entry] = scenario.flatMap({ user, assistant in
//        [.user(user), .assistant(assistant)]
//    })
//    do {
//        let content = try await extractor.extractMemory(from: transcript)
//        print(content)
//    } catch {
//        print(error)
//    }
//}
