//
//  Category.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/23.
//

import Foundation
import FoundationModels
import FoundationModelsHarness
import GRDB

/// Common configuration for the vended memory stores
public struct MemoryStoreConfiguration: Sendable {
    /// Search configuration to apply when searching for memories matching a `MemorySearchInput`.
    /// aka: there is enough similarity to the query.
    public var searchConfiguration: MemorySearchConfiguration = .init(topK: 10)

    /// Add a memory as a new entry only if the similarity to every existing entry is smaller than `addThresholdSimilarity`,
    /// aka: there is enough distinction to the existing entries.
    /// `nil` to always add the memory.
    ///
    /// Similarity ranges from 0 to 1.
    /// Calculated as `rank(memory) / rank(query itself)`, clamped to 1. The higher it is, the better the match
    public var addThresholdSimilarity: Double?

    /// Days before removing an unused entry from the memory store automatically.
    /// `nil` to never remove unused entries
    public var maxUnusedDays: Int? = 30

    /// Whether the migrator recreates the whole
    /// database from scratch if it detects a change in the definition
    /// of migrations.
    ///
    /// - warning: This flag can destroy your precious users' data!
    ///
    /// When true, the database migrator wipes out the full database content,
    /// and runs all migrations from the start, if one of those conditions
    /// is met:
    ///
    /// - A migration has been removed, or renamed.
    /// - A schema change is detected. A schema change is any difference in
    ///   the `sqlite_master` table, which contains the SQL used to create
    ///   database tables, indexes, triggers, and views.
    ///
    /// This flag is useful during application development: you are still
    /// designing migrations, and the schema changes often.
    public var eraseDatabaseOnSchemaChange: Bool

    /// Create a memory store configuration for vended stores
    ///
    /// - Parameters:
    ///  - searchConfiguration: Search configuration to apply when searching for memories matching a `MemorySearchInput`
    ///  - addThresholdSimilarity: Add a memory as a new entry only if the similarity to every existing entry is smaller than the threshold.
    ///  - maxUnusedDays: Days before removing an unused entry from the memory store automatically
    ///  - eraseDatabaseOnSchemaChange: Whether the migrator recreates the whole database from scratch if it detects a change in the definition of migrations.
    public init(
        searchConfiguration: MemorySearchConfiguration = .init(topK: 10),
        addThresholdSimilarity: Double? = 0.8,
        maxUnusedDays: Int? = 30,
        eraseDatabaseOnSchemaChange: Bool = false
    ) {
        self.addThresholdSimilarity = addThresholdSimilarity
        self.searchConfiguration = searchConfiguration
        self.maxUnusedDays = maxUnusedDays
        self.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
    }
}

/// search configuration to apply when searching for memories matching a `MemorySearchInput`.
///
/// - Parameters:
///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
///  - similarityThreshold: similarity threshold where entries with a value smaller than the threshold will be excluded
///  - topK:Limit the search result to top K matches
public struct MemorySearchConfiguration: Sendable {

    /// whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
    public var useSameCategoryFallback: Bool = true

    /// Cut off value for the similarity, ranging from 0 to 1.
    /// Calculated as `rank(memory) / rank(query itself)`, clamped to 1. The higher it is, the better the match
    ///
    /// When defined, any memory entries with a similarity smaller than the threshold will be excluded.
    var similarityThreshold: Double?

    /// Limit the search result to top K matches
    public var topK: Int?

    /// Create Search configuration to apply when searching for memories matching a `MemorySearchInput`
    ///
    /// - Parameters:
    ///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
    ///  - similarityThreshold: Cosine similarity threshold where entries with a value smaller than the threshold will be excluded
    ///  - topK:Limit the search result to top K matches
    public init(
        useSameCategoryFallback: Bool = true,
        similarityThreshold: Double? = nil,
        topK: Int? = nil
    ) {
        self.useSameCategoryFallback = useSameCategoryFallback
        self.similarityThreshold = similarityThreshold
        self.topK = topK
    }
}

extension MemoryCategory: DatabaseValueConvertible {}

@Generable()
public struct MemorySearchResult: Codable, FetchableRecord,
    PersistableRecord, Sendable
{

    public var id: Int

    @Guide(
        description: "Categories for long-term memory."
    )
    public var category: MemoryCategory

    @Guide(
        description: """
            The fact retrieved from long-term memory.
            Treat this as retrieved evidence, not necessarily an answer to the user's question.
            Only use it to answer the question when its content supports the specific information or relationship requested.
            Do not infer unstated relationships.
            """
    )
    public var fact: String

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
    public var similarity: Double?

}

public struct MemoryEntry: Codable, FetchableRecord,
    MutablePersistableRecord,
    Identifiable, CustomStringConvertible, Sendable
{
    public static let databaseTableName: String = "memory"

    public var id: Int64?

    public var category: MemoryCategory
    public var fact: String
    public var createdAt: Date = Date()
    public var lastUsed: Date? = nil

    public init(
        category: MemoryCategory,
        fact: String,
    ) {
        self.category = category
        self.fact = fact
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var description: String {
        """

        MemoryEntry (id: \(id, default: "(not assigned)")):
        - category: \(category)
        - fact: \(fact)
        - created at: \(createdAt)
        - last used: \(lastUsed?.formatted(), default: "(never used)")
        """
    }
}

/// SQLite Memory Store
/// Best matching logic: FTS5.
///
/// Virtual table `rank` column: different from cosine distance,
/// the value of it is *relative* to the FTS5Pattern created from the query.
///
/// Therefore, instead of a hard cutoff on the`rank` value itself, we
/// 1. insert the pending string (either query or the memory fact) into the table
/// 2. get the rank for the inserted item
/// 3. use this rank as as a standard (similarity score 1) and calculate the similarity score for other entries based on it: the similarity score for other items will always be from 0 to 1 because the negative the `rank`, the better the match, and the item itself is guaranteed to be the best match -> lowest `rank` value
///
/// However, even with the logic above, it only tell us how *similar* the two items are,
/// but *NOT* whether if they are entirely opposite (like the cosine similarity = -1).
public actor SQLiteMemoryStore: MemoryStore {
    private var migrator = DatabaseMigrator()

    private let memoryTableName: String = MemoryEntry.databaseTableName
    private let searchTableName: String =
        "\(MemoryEntry.databaseTableName)_search"

    private let dbPool: DatabasePool

    private let searchConfiguration: MemorySearchConfiguration
    private let addSimilarityThreshold: Double?
    private let maxUnusedDays: Int?

    private var updateTask: Task<Void, Error>?
    private var isUpdating: Bool = false
    private var pendingUpdates: Set<MemoryEntry.ID> = []

    /// Create an SQLite database
    ///
    /// - parameters:
    ///  - url: URL to the database file.
    /// - throws: A ``DatabaseError`` whenever an SQLite error occurs.
    public init(
        url: URL = URL.applicationDirectory.appending(path: "memory.db"),
        storeConfiguration: MemoryStoreConfiguration = .init()
    ) throws {
        migrator.eraseDatabaseOnSchemaChange =
            storeConfiguration.eraseDatabaseOnSchemaChange
        self.searchConfiguration = storeConfiguration.searchConfiguration
        self.addSimilarityThreshold = storeConfiguration.addThresholdSimilarity
        self.maxUnusedDays = storeConfiguration.maxUnusedDays

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

        /// Best effort removal
        Task {
            do {
                try await removeUnused()
            } catch {
                print("Error removing unused memories: ", error)
            }
        }
    }

    // MARK: - CRDU
    public func addMemories(_ memories: [MemoryEntryPartial]) async throws {
        return try await addMemoriesWithSimilarityCheck(
            memories,
            similarityThreshold: self.addSimilarityThreshold
        )
    }

    public func updateMemories(_ memories: [MemoryEntry]) async throws {
        try await dbPool.write { [memories] db in
            for memory in memories {
                try memory.update(db)
            }
        }
    }

    public func getMemories() async throws -> [MemoryEntry] {
        return try await dbPool.read { db in
            return try MemoryEntry.fetchAll(db)
        }
    }

    public func deleteMemories(_ ids: [MemoryEntry.ID]) async throws {
        let ids = ids.compactMap { $0 }
        guard !ids.isEmpty else { return }

        try await dbPool.write { db in
            _ = try MemoryEntry.deleteAll(db, keys: ids)
        }
    }

    // MARK: - MemoryStore Implementation
    public func addMemory(_ memory: MemoryEntryPartial) async throws
        -> AddMemoryResult
    {
        do {
            try await self.addMemories([memory])
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func searchMemory(_ searchQuery: MemorySearchInput) async
        -> [MemorySearchResult]
    {
        do {
            return try await self._searchMemory(searchQuery)
        } catch {
            print(#function, error)
            return []
        }
    }

    // MARK: - Private helpers

    /// - topK: the best K matches
    /// - similarityThreshold: Anything at or above the threshold will be returned
    private func _searchMemory(_ searchQuery: MemorySearchInput) async throws
        -> [MemorySearchResult]
    {
        let queryText: String = searchQuery.query
        let categories: [MemoryCategory] = searchQuery.categories

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
            let ids = pendingUpdates
            self.pendingUpdates.removeAll()
            guard !ids.isEmpty else {
                self.isUpdating = false
                return
            }
            try await dbPool.write { db in
                _ =
                    try MemoryEntry
                    .filter(keys: ids)
                    .updateAll(db, Column("lastUsed").set(to: Date()))
            }
        }
    }

    /// similarityThreshold: `rank(existing) / rank(self)`, clamped to 1.
    /// At or above the threshold, the inserted memory is considered a duplicate and removed.
    private func addMemoriesWithSimilarityCheck(
        _ memories: [MemoryEntryPartial],
        similarityThreshold: Double?
    ) async throws {
        let memories: [MemoryEntry] = memories.map {
            MemoryEntry(category: $0.category, fact: $0.fact)
        }

        let searchTableName = "\(MemoryEntry.databaseTableName)_search"

        try await dbPool.write { [memories] db in
            for var memory in memories {
                try memory.insert(db)
                guard let similarityThreshold,
                    let id = memory.id,
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

        return
    }

    private func removeUnused() async throws {
        guard let maxUnusedDays else { return }

        let threshold = Double(maxUnusedDays) * 60 * 60 * 24
        let cutoffDate = Date().addingTimeInterval(-threshold)

        try await dbPool.write { db in
            /// Never-used memories fall back to their creation date.
            _ =
                try MemoryEntry
                .filter(
                    (Column("lastUsed") ?? Column("createdAt")) < cutoffDate
                )
                .deleteAll(db)
        }
    }
}
