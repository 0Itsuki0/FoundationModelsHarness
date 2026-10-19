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
class MemoryPlugin /*: Plugin*/ {
    static let name: PluginName = "FoundationModelsHarness_MemoryPlugin"

    let hooks: [any HookEventHandler] = []

    let tools: [ToolConfig] = []

    //    let enableAutoExtraction: Bool
    // true to add a extractor that extract queries to be written to memory every x turns
    // because  You also don't want to rely on the main LLM remembering to call add_memory, which was the reason automatic extraction exists in the first place.
}

/// Automatic-memory-extraction configuration.
public struct MemoryAutoExtractionConfig {
    /// Extractor to transform conversation messages into discrete, searchable entries.
    public let extractor: MemoryExtractor

    /// turns to buffer before running extraction. Default to 5.
    public let turnBufferCount: Int

    public init(extractor: MemoryExtractor, turnBufferCount: Int = 5) {
        self.extractor = extractor
        self.turnBufferCount = turnBufferCount
    }
}

public protocol MemoryStore {
    /// Search the store for entries matching the query, ordered by relevance
    func addMemory() async throws

    /// Add a single piece of content to the store
    func searchMemory() async throws
}

extension MemoryStore {
    public func onNewTranscript() {}
}

/// Transforms conversation messages into discrete, searchable entries.
public protocol MemoryExtractor {
    /// - Parameters:
    ///   - messages: filtered messages (only prompt and response) to extract from
    func extractMemory(from messages: [Transcript.Entry]) async throws
        -> [ExtractionResult]
}

/// A discrete entry produced by a `MemoryExtractor`, ready to be written to a store via its `MemoryStore.addMemory`.
public struct ExtractionResult {
    let content: String
    let metadata: [String: JSONValue]?
}

public class LanguageModelExtractor: MemoryExtractor {
    public static let defaultInstruction = """
        You extract durable facts worth remembering across future conversations from a transcript.

        **RULE**:
        - Return ONLY a JSON array of objects, each: {"content": string}. 
        - Each object is one discrete, self-contained fact (a preference, decision, or stable detail about the user or task). 
        - Do **not** include transient chit-chat, questions, or anything already obvious. 
        - If there is nothing worth remembering, return [].
        """

    private let session: LanguageModelSession

    init(
        model: any LanguageModel = SystemLanguageModel(),
        instruction: Instructions = Instructions {
            LanguageModelExtractor.defaultInstruction
        }
    ) {
        self.session = LanguageModelSession(
            model: model,
            instructions: instruction
        )
    }

    public func extractMemory(from messages: [Transcript.Entry]) async throws
        -> [ExtractionResult]
    {
        /// Not using the Agent wrapper here since it is just one turn call without tools / retries.
        self.clearSessionHistory()

        return []
    }

    /// remove all conversational entries
    private func clearSessionHistory() {
        self.session.transcript.history.removeAll()
    }
}

private struct AddMemoryTool: Tool {
    let name = "add_memory"
    let description =
        "Add facts, preferences, or decisions to long-term memory so they are remembered across conversations. Use when the user shares something worth recalling later."

    /// accessing states from the tools if necessary
    @SessionProperty(\.agentState)
    private var agentState

    @SessionProperty(\.invocationState)
    private var invocationState

    @Generable
    struct Arguments {
        @Guide(description: "The name to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        print("Tool[\(name)] called with arguments: \(arguments)")
        return "Hello \(arguments.name)"
    }
}

private struct SearchMemoryTool: Tool {
    let name = "search_memory"
    let description =
        "Search long-term memory for facts, preferences, or context from previous conversations. Use when you need background about the user or topic that may have been discussed before."

    /// accessing states from the tools if necessary
    @SessionProperty(\.agentState)
    private var agentState

    @SessionProperty(\.invocationState)
    private var invocationState

    @Generable
    struct Arguments {
        @Guide(description: "The name to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        print("Tool[\(name)] called with arguments: \(arguments)")
        return "Hello \(arguments.name)"
    }
}
