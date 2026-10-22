//
//  MemoryPlugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/19.
//

// MEMO: strands-ts/src/memory/memory-manager.ts
// Vended memory store: strands-ts/src/vended-memory-stores/file-memory-store/store.ts
// memory extraction: strands-ts/src/memory/extraction/model-extractor.ts

import FoundationModels

/// Non-public to avoid re-using one instance for multiple agent.
class MemoryPlugin: Plugin {

    static let name: PluginName = "FoundationModelsHarness_MemoryPlugin"

    func initAgent(_ agent: Agent) async -> PluginInitResult {
        return PluginInitResult(addedHooks: [], addedTools: [])
    }

    func deInitAgent(_ agent: Agent) async {

    }

    //    let hooks: [any HookEventHandler] = []
    //
    //    let tools: [ToolConfig] = []

    //    let enableAutoExtraction: Bool
    // true to add a extractor that extract queries to be written to memory every x turns
    // because  You also don't want to rely on the main LLM remembering to call add_memory, which was the reason automatic extraction exists in the first place.
}

/// Automatic-memory-extraction configuration.
public struct MemoryAutoExtractionConfig<T: MemoryExtractor> {
    /// Extractor to transform conversation messages into discrete, searchable entries.
    public let extractor: T

    /// turns to buffer before running extraction. Default to 5.
    public let turnBufferCount: Int

    public let onExtraction: (T.ExtractionResult) async -> Void

    public init(
        extractor: T,
        turnBufferCount: Int,
        onExtraction: @escaping (T.ExtractionResult) async -> Void
    ) {
        self.extractor = extractor
        self.turnBufferCount = turnBufferCount
        self.onExtraction = onExtraction
    }
}

public protocol MemoryStore {
    /// A single memory entry retrieved from or to be added to a memory store.
    associatedtype
        MemoryEntry: ConvertibleFromGeneratedContent & PromptRepresentable

    /// Add a single piece of content to the store
    func addMemory(_ entry: MemoryEntry) async throws

    /// Search the store for entries matching the query, ordered by relevance
    func searchMemory() async throws -> [MemoryEntry]
}

/// Transforms conversation messages into discrete, searchable entries.
public protocol MemoryExtractor {
    associatedtype ExtractionResult

    /// - Parameters:
    ///   - messages: filtered messages (only prompt and response) to extract from
    func extractMemory(from messages: [Transcript.Entry]) async throws
        -> [ExtractionResult]
}

/// A discrete entry produced by a `MemoryExtractor`, ready to be written to a store via its `MemoryStore.addMemory`.
//public struct ExtractionResult {
//    let content: String
//    let metadata: [String: JSONValue]?
//}

/// JSON File MemoryStore: An entry per fact: {category, fact, ts}
///
/// Categories:
/// About the user
/// - identity: name, role, timezone, language
/// - preferences: style, formatting, tools, tone
/// - goals: what they're working toward
/// - constraints: things to avoid, hard rules
/// - feedback: corrections given to the agent
///
/// About the work
/// - project: architecture, stack, key files, status
/// - conventions: code style, naming, team norms
/// - decisions: choices made and why
/// - procedures: how to do recurring tasks (deploy, release, test)
/// - issues: known bugs, gotchas, workarounds
///
/// About the world
/// - people: teammates, contacts, who owns what
/// - references: URLs, docs, dashboards, tickets
/// - facts: general knowledge that doesn't fit elsewhere
///
/// About time
/// - events: things that happened, with dates
/// - tasks: open to-dos and follow-ups
class FileMemoryStore {

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
}

/// SQLite + FTS5 MemoryStore
class SQLiteMemoryStore {}

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
