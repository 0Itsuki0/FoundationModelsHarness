//
//  MemoryPlugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/19.
//

import FoundationModels

/// Configure how the tool will be added to the agent
public struct ToolOption: Sendable {
    /// Boolean flag on whether to add the tool to the agent
    public var enabled: Bool

    /// override the tool name
    public var nameOverride: String? = nil

    /// override the tool description
    public var descriptionOverride: String? = nil
    
    /// System instruction to be injected to the Agent's instruction.
    public var additionalInstruction: Instructions?

    public init(
        enabled: Bool,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil,
        additionalInstruction: Instructions? = nil
    ) {
        self.enabled = enabled
        self.nameOverride = nameOverride
        self.descriptionOverride = descriptionOverride
        self.additionalInstruction = additionalInstruction
    }
}

/// Automatic-memory-extraction configuration.
/// Add a memory extractor that extract queries to be written to memory every x turns.
public struct MemoryAutoExtractionConfig<T: MemoryExtractor>: Sendable {
    /// Extractor to transform conversation messages into discrete, searchable memory entries.
    public let extractor: T

    /// turns to buffer before running extraction. Default to 5.
    public let turnBufferCount: Int

    /// Handle extraction results, for example, to transform the `ExtractionResult` to a type accepts by the `MemoryStore`
    public let onExtraction:
        @Sendable (Result<T.ExtractionResult, Error>) async -> Void

    /// Create an automatic-memory-extraction configuration.
    ///
    /// - Parameters:
    ///   - extractor: Memory Extractor to transform conversation messages into discrete, searchable entries
    ///   - turnBufferCount: turns to buffer the messages before running extraction. Default to 5.
    ///   - onExtraction:extraction results handler
    public init(
        extractor: T,
        turnBufferCount: Int = 5,
        onExtraction:
            @Sendable @escaping (Result<T.ExtractionResult, Error>) async ->
            Void
    ) {
        self.extractor = extractor
        self.turnBufferCount = turnBufferCount
        self.onExtraction = onExtraction
    }
}

/// Configuration for agent's long term memory
public struct AgentMemoryConfiguration<
    Store: MemoryStore,
    Extractor: MemoryExtractor
>: Sendable {

    /// Memory store to
    /// 1. persist long-term memory
    /// 2. supply search results
    public var store: Store

    /// Automatic-memory-extraction configuration to extract long-term memory automatically
    public var autoExtraction: MemoryAutoExtractionConfig<Extractor>?

    /// Tool configurations on `AddMemoryTool`
    /// Recommend to disable this tool and use `autoExtraction` instead.
    public var addMemoryToolConfig: ToolOption

    /// Tool configurations on `SearchMemoryTool`
    /// Recommend to add in the system instruction injection as in `MemoryToolDefault.searchToolSystemInjection`
    public var searchMemoryToolConfig: ToolOption

    /// Create a configuration for agent's long term memory
    ///
    /// - Parameters:
    ///   - store: Memory store
    ///   - autoExtraction: Automatic-memory-extraction configuration to extract long-term memory automatically
    ///   - addMemoryToolConfig: Tool configurations on `AddMemoryTool`. Recommend to disable this tool and use `autoExtraction` instead.
    ///   - searchMemoryToolConfig Tool configurations on `SearchMemoryTool`
    public init(
        store: Store,
        autoExtraction: MemoryAutoExtractionConfig<Extractor>,
        addMemoryToolConfig: ToolOption,
        searchMemoryToolConfig: ToolOption
    ) {
        self.store = store
        self.autoExtraction = autoExtraction
        self.addMemoryToolConfig = addMemoryToolConfig
        self.searchMemoryToolConfig = searchMemoryToolConfig
    }
}

extension AgentMemoryConfiguration where Extractor == DisabledExtractor {
    /// Create a configuration for agent's long term memory disabling auto extraction
    ///
    /// - Parameters:
    ///   - store: Memory store
    ///   - addMemoryToolConfig: Tool configurations on `AddMemoryTool`.
    ///   - searchMemoryToolConfig Tool configurations on `SearchMemoryTool`
    public init(
        store: Store,
        addMemoryToolConfig: ToolOption,
        searchMemoryToolConfig: ToolOption
    ) {
        self.store = store
        self.autoExtraction = nil
        self.addMemoryToolConfig = addMemoryToolConfig
        self.searchMemoryToolConfig = searchMemoryToolConfig
    }
}

/// A shadow type to disable auto extraction
/// Exported only so that the `init(store:,addMemoryTool: ,searchMemoryTool: )` can be exported as public
public actor DisabledExtractor: MemoryExtractor {
    public func extractMemory(from messages: [Transcript.Entry]) async throws {
        fatalError()
    }
    public typealias ExtractionResult = Void
}

/// Non-public to avoid re-using one instance for multiple agent.
actor MemoryPlugin<
    Store: MemoryStore,
    Extractor: MemoryExtractor
>: Plugin {

    static var name: PluginName { "FoundationModelsHarness_MemoryPlugin" }

    private let configuration: AgentMemoryConfiguration<Store, Extractor>

    private var bufferedMessages: [Transcript.Entry] = []

    init(configuration: AgentMemoryConfiguration<Store, Extractor>) {
        self.configuration = configuration
    }

    func initAgent(_ agent: Agent) -> PluginInitResult {
        var tools: [ToolName] = []
        var hooks: [HookID] = []
        let store = configuration.store
        let addToolConfig = configuration.addMemoryToolConfig
        let searchToolConfig = configuration.searchMemoryToolConfig
        if addToolConfig.enabled {
            let addMemoryTool = AddMemoryTool(
                call: { argument in
                    return try await store.addMemory(argument)
                },
                nameOverride: addToolConfig.nameOverride,
                descriptionOverride: addToolConfig.descriptionOverride
            )
            agent.addTool(.init(tool: addMemoryTool))
            tools.append(addMemoryTool.name)
        }

        if searchToolConfig.enabled {
            let searchMemoryTool = SearchMemoryTool(
                call: { argument in
                    return try await store.searchMemory(argument)
                },
                nameOverride: searchToolConfig.nameOverride,
                descriptionOverride: searchToolConfig.descriptionOverride
            )
            agent.addTool(.init(tool: searchMemoryTool))
            tools.append(searchMemoryTool.name)
        }

        if configuration.autoExtraction != nil {
            let hookId = agent.addHook(
                AfterInvocationEventHandler(
                    callback: { self.handleAfterInvocation($0) },
                    options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
                )
            )
            hooks.append(hookId)
        }

        return PluginInitResult(addedHooks: hooks, addedTools: tools)
    }

    func deInitAgent(_ agent: Agent) {
        self.flushBufferedMemories()
    }

    private func flushBufferedMemories() {
        self.startExtractionIfNecessary(checkBufferCount: false)
    }

    private func handleAfterInvocation(
        _ event: AfterInvocationEventHandler.EventPayload
    ) {
        let history = event.agent.history

        /// extract last turn
        guard
            let lastIndex = history.lastIndex(where: {
                $0.asPrompt != nil
            })
        else {
            return
        }

        let lastTurn = history[lastIndex...]
        self.bufferedMessages.append(contentsOf: lastTurn)
        self.startExtractionIfNecessary()
    }

    /// Not awaiting here to perform the extraction in the background.
    private func startExtractionIfNecessary(checkBufferCount: Bool = true) {
        guard let extractionConfig = self.configuration.autoExtraction,
            !(extractionConfig.extractor is DisabledExtractor)
        else {
            self.bufferedMessages = []
            return
        }

        let turnCount = self.bufferedMessages.count(where: {
            $0.asPrompt != nil
        })

        if checkBufferCount, turnCount < extractionConfig.turnBufferCount {
            return
        }

        let extractorInput = self.bufferedMessages
        self.bufferedMessages.removeAll()

        let extractor = extractionConfig.extractor
        let onExtraction = extractionConfig.onExtraction
        Task { [extractor, onExtraction] in
            do {
                let result = try await extractor.extractMemory(
                    from: extractorInput
                )
                await onExtraction(.success(result))
            } catch {
                await onExtraction(.failure(error))
            }
        }
    }
}

public protocol MemoryStore: Sendable {
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
public protocol MemoryExtractor: Sendable {
    associatedtype ExtractionResult: Sendable

    /// - Parameters:
    ///   - messages: messages (excluding instruction, but include tool use / tool output) to extract from. The message count  here depends on the `MemoryAutoExtractionConfig.turnBuffer` count.
    func extractMemory(from messages: [Transcript.Entry]) async throws
        -> ExtractionResult
}

public enum MemoryToolDefault {
    public static let addToolName = "add_llm_memory"
    public static let addToolDescription = """
        Save information to **Assistant's** long-term memory for recall in future conversations.
        - Save multi-word, concise, self-contained fact that preserves its original meaning and important relationships. NEVER Sentence.
        """

    public static let searchToolName = "search_user_info"
    public static let searchToolDescription = """
        Look up user-related information such as preferences, rules, relationships, and tasks.
        - Search with multi-word query. NEVER Sentence.
        """

    /// Recommended instruction to add if enabling search tool to better instruct the Language Model
    public static func searchToolSystemInjection(
        searchToolName: String = MemoryToolDefault.searchToolName
    ) -> String {
        """
        Look up information about the user using the [\(searchToolName)] tool **whenever** knowing their preferences, works, tasks, or relationships *COULD possibly* make you better assistant them.
        - Use the tool **proactively**. Do NOT wait for the user to prompt you explicitly to use it.
        - Only use it as a reference. It is not guaranteed to be correct. It can be out-of-date. 
        - If it is different from what the user says, ignore the results. **Never** question what the user says because of the results. The user is always correct.
        - Always answer in natural tone.
        - If there is no results, answer normally.
        - Never inform the user about the search result.
        """
    }
}

struct AddMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    var name = MemoryToolDefault.addToolName
    var description = MemoryToolDefault.addToolDescription

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

    var name = MemoryToolDefault.searchToolName
    var description = MemoryToolDefault.searchToolDescription

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
