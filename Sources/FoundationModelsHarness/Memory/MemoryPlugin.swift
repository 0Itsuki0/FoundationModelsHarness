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

public class LanguageModelExtractor /*: MemoryExtractor*/ {
    public static let defaultInstruction = """
        You extract durable facts worth remembering across future conversations from a transcript.

        **RULE**:
        - Return ONLY a JSON array of objects, each: {"content": string}. 
        - Each object is one discrete, self-contained fact (a preference, decision, or stable detail about the user or task). 
        - Do **not** include transient chit-chat, questions, or anything already obvious. 
        - If there is nothing worth remembering, return [].
        """

    public typealias DefaultOutput = [String]

    //    public struct StructuredOutput {
    //        let schema: GenerationSchema
    //        let convert: (GeneratedContent) throws -> [ExtractionResult]
    //
    //        init(
    //            schema: GenerationSchema = DefaultOutput.self.generationSchema,
    //            convert: @escaping (GeneratedContent) throws -> [ExtractionResult] =
    //                {
    //                    rawContent in
    //                    let value: DefaultOutput = try rawContent.value()
    //                    return value.map({
    //                        ExtractionResult(content: $0, metadata: nil)
    //                    })
    //                }
    //        ) {
    //            self.schema = schema
    //            self.convert = convert
    //        }
    //    }
    //
    //    public struct Structured<T:ConvertibleFromGeneratedContent> {
    //        let type: T
    //        let convert: (T) throws -> [ExtractionResult]
    //
    //        init(
    //            type: T = DefaultOutput.self,
    //            convert: @escaping (GeneratedContent) throws -> [ExtractionResult] =
    //            {
    //                rawContent in
    //                let value: DefaultOutput = try rawContent.value()
    //                return value.map({
    //            ExtractionResult(content: $0, metadata: nil)
    //        })
    //            }
    //        ) {
    //            self.schema = schema
    //            self.convert = convert
    //        }
    //    }

    private let session: LanguageModelSession

    init(
        model: any LanguageModel = SystemLanguageModel(),
        instruction: Instructions = Instructions {
            LanguageModelExtractor.defaultInstruction
        },
        //        structuredOutput: StructuredOutput = StructuredOutput()
    ) {
        self.session = LanguageModelSession(
            model: model,
            instructions: instruction
        )
    }

    public func extractMemory(from messages: [Transcript.Entry])
        async throws  //        -> [ExtractionResult]
    {
        /// Not using the Agent wrapper here since it is just one turn call without tools / retries.
        self.clearSessionHistory()

        return
    }

    private func buildPrompt(from messages: [Transcript.Entry]) -> String {
        return messages.map(\.description).joined(separator: "\n")
    }

    /// remove all conversational entries
    private func clearSessionHistory() {
        self.session.transcript.history.removeAll()
    }
}


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
    
    @Generable(description: """
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
    """)
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

