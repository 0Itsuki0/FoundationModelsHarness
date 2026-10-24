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
    associatedtype AddMemoryInput: Generable
    associatedtype AddMemoryResult: PromptRepresentable

    /// Add a single piece of content to the store
    func addMemory(_ input: AddMemoryInput) async throws -> AddMemoryResult

    associatedtype SearchMemoryInput: Generable
    associatedtype SearchMemoryResult: PromptRepresentable

    /// Search the store for entries matching the query
    func searchMemory(_ input: SearchMemoryInput) async throws
        -> SearchMemoryResult
}

/// Transforms conversation messages into discrete, searchable entries.
public protocol MemoryExtractor {
    associatedtype ExtractionResult

    /// - Parameters:
    ///   - messages: filtered messages (only prompt and response) to extract from
    func extractMemory(from messages: [Transcript.Entry]) async throws
        -> [ExtractionResult]
}

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
        Look up user-related information such as preferences, rules, relationships, and tasks.
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
