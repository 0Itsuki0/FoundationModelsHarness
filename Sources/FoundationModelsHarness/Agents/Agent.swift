//
//  Agent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import SwiftUI

/// Public `SessionPropertyValues` for possible access from the tools
extension SessionPropertyValues {
    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    @SessionPropertyEntry
    public var agentState: AgentState = [:]

    /// Invocation state accessible to tools and application logic.
    /// Lives for a single invocation.
    /// State is not passed to the model during inference.
    @SessionPropertyEntry
    public var invocationState: InvocationState = [:]

}

/// Package `SessionPropertyValues`
///
/// Using `SessionPropertyValues` instead of storing directly because `Agent` cannot store mutable or non-sendable values
extension SessionPropertyValues {
    /// Tools registered to the agent.
    @SessionPropertyEntry
    public var tools: [ToolConfig] = []

    /// Default invocation options that will be used when building respond / streamResponse request.
    @SessionPropertyEntry
    public var defaultInvocationOptions: InvocationOptions = InvocationOptions()

    /// Instruction used by the model
    @SessionPropertyEntry
    public var instruction: Instructions = Instructions {}

    /// Current model used by the agent.
    @SessionPropertyEntry
    public var model: any LanguageModel = SystemLanguageModel()

    @SessionPropertyEntry
    var hookRegistry: HookRegistry = .init()

    @SessionPropertyEntry
    var pluginRegistry: PluginRegistry = .init()
}

public typealias InvocationState = [String: JSONValue]
public typealias AgentState = [String: JSONValue]

public struct InvocationOptions: Sendable {
    public var schema: GenerationSchema
    public var options: GenerationOptions
    public var metadata: [String: GeneratedContent]
    public var contextOptions: ContextOptions
    public var invocationState: InvocationState
    public var toolExecutionMode: ToolExecutionMode

    public init(
        schema: GenerationSchema = String.self.generationSchema,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
    ) {
        self.schema = schema
        self.options = options
        self.metadata = metadata.mapValues({ $0.generatedContent })
        self.contextOptions = contextOptions
        self.invocationState = invocationState
        self.toolExecutionMode = toolExecutionMode
    }

    public init<Content: Generable>(
        generating type: Content.Type = String.self,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
    ) {
        self.schema = Content.generationSchema
        self.options = options
        self.metadata = metadata.mapValues({ $0.generatedContent })
        self.contextOptions = contextOptions
        self.invocationState = invocationState
        self.toolExecutionMode = toolExecutionMode
    }
}

extension Transcript.Prompt {
    static let dummyPrompt = Transcript.Prompt(
        metadata: [InternalMetadataKey.dummyPrompt: true],
        segments: [],
    )
}

@Observable
public final class Agent: Sendable {

    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    public var agentState: AgentState {
        get {
            session.properties.agentState
        }
        set {
            session.properties.agentState = newValue
        }
    }

    /// Current model used by the agent.
    public var model: any LanguageModel {
        get {
            session.properties.model
        }
        set {
            session.properties.model = newValue
        }
    }

    /// Instruction used by the model
    public var instruction: Instructions {
        get {
            session.properties.instruction
        }
        set {
            let new = ToolDelegationPlugin.injectDelegationPrompt(
                for: tools,
                on: newValue
            )
            session.properties.instruction = new
        }
    }

    /// Default invocation options that will be used when building respond / streamResponse request.
    public var defaultInvocationOptions: InvocationOptions {
        get {
            session.properties.defaultInvocationOptions
        }
        set {
            session.properties.defaultInvocationOptions = newValue
        }
    }

    public private(set) var history: Transcript.HistoryView {
        get {
            session.transcript.history
        }
        set {
            session.transcript.history = newValue
        }
    }

    /// Tools registered to the agent.
    public private(set) var tools: [ToolConfig] {
        get {
            session.properties.tools
        }
        set {
            session.properties.tools = newValue
        }
    }

    private let session: LanguageModelSession

    private var invocationState: InvocationState {
        get {
            session.properties.invocationState
        }
        set {
            session.properties.invocationState = newValue
        }
    }

    private var hookRegistry: HookRegistry {
        session.properties.hookRegistry
    }

    private var pluginRegistry: PluginRegistry {
        session.properties.pluginRegistry
    }

    private var delegatedToolName: [String] {
        self.tools.filter({ $0.delegate }).map(\.invocableTool.name)
    }

    private func isDelegatedTool(_ toolName: String) -> Bool {
        self.delegatedToolName.contains(toolName)
    }

    
    /// Create an agent with configurations.
    ///
    /// - Parameters:
    ///  - model: model used by the agent. Gettable/Settable using `Agent.model`.
    ///  - tools: tools to added to the agent. Gettable using `Agent.tools`, settable using `addTool`/`removeTool`.
    ///  - instruction: Instruction used by the model. Gettable/Settable using `Agent.instruction`.
    ///  - defaultInvocationOptions: Default invocation options that will be used when building respond / streamResponse request. Gettable/Settable using `Agent.defaultInvocationOptions`.
    ///  - history: Existing transcript entries *without* the initial instructions.
    public init(
        model: any LanguageModel = SystemLanguageModel(),
        tools: [ToolConfig] = [],
        instruction: Instructions = Instructions {},
        defaultInvocationOptions: InvocationOptions = InvocationOptions(),
        history: [Transcript.Entry] = []
    ) {
        let instruction = ToolDelegationPlugin.injectDelegationPrompt(
            for: tools,
            on: instruction
        )
        let profile = AgentProfile()
        let session = LanguageModelSession(profile: profile, history: history)
        self.session = session
        self.tools = tools
        self.instruction = instruction
        self.model = model
        self.defaultInvocationOptions = defaultInvocationOptions
        self.setupBuiltInHooks()
    }

    private func setupBuiltInHooks() {
        self.addPlugin(ToolDelegationPlugin(self.delegatedToolName))
    }

    @discardableResult
    public func addPlugin<T: Plugin>(_ plugin: T) -> String {
        return self.pluginRegistry.registerPlugin(plugin, to: self)
    }

    public func removePlugin(_ name: String) {
        self.pluginRegistry.removePlugin(name, from: self)
    }

    @discardableResult
    public func addTool(_ tool: ToolConfig) -> String {
        self.removeTool(tool.toolName)
        self.tools.append(tool)
        return tool.toolName
    }

    public func removeTool(_ name: String) {
        self.tools.removeAll(where: { $0.toolName == name })
    }

    @discardableResult
    public func addHook(_ hook: any HookEventHandler) -> HookID {
        return self.hookRegistry.addHook(hook)
    }

    public func removeHook(_ id: HookID) {
        self.hookRegistry.removeHook(id)
    }

    public func removeHooks(for types: Set<HookEventType>) {
        self.hookRegistry.removeHooks(for: types)
    }

    public func removeAllHooks() {
        self.hookRegistry.removeAllHooks()
    }

    private func resetInvocationState() {
        self.invocationState = .init()
    }

    /// Produces a generated content type as a response to a prompt and schema.
    ///
    /// - Parameters:
    ///   - prompt: A prompt for the model to respond to.
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    ///   - toolExecutionMode: Strategy for executing tool calls that the model emits in a single assistant turn.
    ///
    /// Passing nil for parameters other than `prompt` to use the `defaultInvocationOptions`.
    @discardableResult
    public func respond(
        to prompt: String,
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
    ) async -> AgentResult {
        return await self.respond(
            to: Prompt(prompt),
            schema: schema,
            options: options,
            metadata: metadata,
            contextOptions: contextOptions,
            invocationState: invocationState,
            toolExecutionMode: toolExecutionMode
        )
    }

    /// Produces a generated content type as a response to a prompt and schema.
    ///
    /// - Parameters:
    ///   - prompt: A prompt for the model to respond to.
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    ///   - toolExecutionMode: Strategy for executing tool calls that the model emits in a single assistant turn.
    ///
    /// Passing nil for parameters other than `prompt` to use the `defaultInvocationOptions`.
    @discardableResult
    public func respond(
        to prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
    ) async -> AgentResult {
        return await runInvocation(
            on: Prompt(prompt),
            schema: schema,
            options: options,
            metadata: metadata,
            contextOptions: contextOptions,
            invocationState: invocationState,
            toolExecutionMode: toolExecutionMode,
            currentAttempt: 1,
            session: session,
            streamingInto: nil
        )
    }

    private func buildInvocationOptions(
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
    ) -> InvocationOptions {
        return InvocationOptions(
            schema: schema ?? defaultInvocationOptions.schema,
            options: options ?? defaultInvocationOptions.options,
            metadata: metadata ?? defaultInvocationOptions.metadata,
            contextOptions: contextOptions
                ?? defaultInvocationOptions.contextOptions,
            invocationState: invocationState
                ?? defaultInvocationOptions.invocationState,
            toolExecutionMode: toolExecutionMode
                ?? defaultInvocationOptions.toolExecutionMode
        )
    }

    /// One-Invocation wrapper.
    @discardableResult
    private func runInvocation(
        on prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
        currentAttempt: Int,
        session: LanguageModelSession,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async -> AgentResult {
        let resolvedOptions = buildInvocationOptions(
            schema: schema,
            options: options,
            metadata: metadata,
            contextOptions: contextOptions,
            invocationState: invocationState,
            toolExecutionMode: toolExecutionMode
        )

        let schema = resolvedOptions.schema
        let options = resolvedOptions.options
        let metadata = resolvedOptions.metadata
        let contextOptions = resolvedOptions.contextOptions
        let invocationState = resolvedOptions.invocationState
        let toolExecutionMode = resolvedOptions.toolExecutionMode

        self.resetInvocationState()
        self.invocationState = invocationState

        var promptTranscript = await Transcript.Prompt(
            metadata: metadata,
            segments: SegmentBuilder.segments(from: prompt),
            options: options,
            responseFormat: Transcript.ResponseFormat(schema: schema),
            contextOptions: contextOptions
        )

        var agentResult: AgentResult

        let beforeInvocationResult = await beforeInvocation(
            prompt: promptTranscript
        )

        switch beforeInvocationResult {
        case .cancelled(let response):
            /// prompt and response already added to the history. simply set the result here.
            /// No need to call `afterModelCall` here for clean-up because `beforeModelCall` is never called.
            agentResult = AgentResult(
                response: response,
                invocationState: invocationState,
                usage: .zero
            )
        case .continue(let updated):
            promptTranscript = updated
            agentResult = await runAgentLoop(
                on: promptTranscript,
                session: session,
                toolExecutionMode: toolExecutionMode,
                streamingInto: continuation
            )
        }

        continuation?.yield(.init(result: agentResult, usage: .zero))

        /// there shouldn't be any left, but just as an extra defensive check here.
        self.history.removeDummyPrompt()

        let afterInvocationResult = await self.afterInvocation(
            result: agentResult,
            currentAttempt: currentAttempt
        )

        switch afterInvocationResult {
        case .resume(let newPrompt):
            return await runInvocation(
                on: newPrompt,
                schema: schema,
                options: options,
                metadata: metadata,
                contextOptions: contextOptions,
                /// using the updated invocation state, instead of the one in the argument
                invocationState: self.invocationState,
                toolExecutionMode: toolExecutionMode,
                currentAttempt: 1,
                session: session,
                streamingInto: continuation
            )
        case .retry:
            self.history = self.history.prefix(while: {
                $0.id != promptTranscript.id
            })
            return await runInvocation(
                on: prompt,
                schema: schema,
                options: options,
                metadata: metadata,
                contextOptions: contextOptions,
                /// using the updated invocation state, instead of the one in the argument
                invocationState: self.invocationState,
                toolExecutionMode: toolExecutionMode,
                currentAttempt: currentAttempt + 1,
                session: session,
                streamingInto: continuation
            )
        case .finish:
            break
        }

        self.resetInvocationState()

        return agentResult
    }

    /// agent loop.
    ///
    /// `continuation`: passed in if streaming.
    /// Important: **Never** call `continuation.finish` here
    private func runAgentLoop(
        on prompt: Transcript.Prompt,
        session: LanguageModelSession,
        toolExecutionMode: ToolExecutionMode,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async -> AgentResult {
        let beforeCallUsage = session.usage

        var modelStopData = await invokeModel(
            prompt: prompt,
            currentAttempt: 1,
            session: session,
            streamingInto: continuation
        )

        agentLoop: while true {
            let usage = calculateUsageDiff(
                before: beforeCallUsage,
                after: session.usage
            )

            switch modelStopData.stopReason {

            case .endTurn(let response):
                return AgentResult(
                    response: response,
                    invocationState: invocationState,
                    usage: usage
                )
            case .refusal(let error):
                return AgentResult(
                    error: error,
                    invocationState: invocationState,
                    usage: usage
                )
            case .toolUse(let toolCall):
                let results = await self.callTools(
                    toolCall,
                    mode: toolExecutionMode,
                    streamingInto: continuation
                )

                switch results {
                case .continue(let toolCallResults):
                    let error: [ToolCallError] =
                        toolCallResults
                        .compactMap { result -> ToolCallError? in
                            switch result.result {
                            case .success(_):
                                return nil
                            case .failure(let value):
                                return ToolCallError(
                                    toolCall: result.toolCall,
                                    error: value
                                )
                            }
                        }

                    if !error.isEmpty {
                        return AgentResult(
                            error: error,
                            invocationState: invocationState,
                            usage: usage
                        )
                    }

                    modelStopData = await self.invokeModel(
                        prompt: nil,
                        currentAttempt: 1,
                        session: session,
                        streamingInto: continuation
                    )

                case .endTurn(let response):
                    return AgentResult(
                        response: response,
                        invocationState: invocationState,
                        usage: usage
                    )
                }

                continue
            }
        }
    }

    /// `prompt`: `nil` for not adding new prompt to the existing `history`,
    /// aka: when trying to generate a response based on tool output
    ///
    /// `continuation`: passed in if streaming.
    /// Important: **Never** call `continuation.finish` here
    private func invokeModel(
        prompt: Transcript.Prompt?,
        currentAttempt: Int,
        session: LanguageModelSession,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async -> ModelStopData {

        let beforeCallUsage = session.usage

        if let prompt {
            /// Always add the prompt transcript programmatically and then send a dummy prompt to trigger model
            /// to handle invocation handlers / model handlers prompt modification
            self.history.append(.prompt(prompt))
        }

        var modelStopData: ModelStopData

        /// `history` in `BeforeModelCall` hook should contain the last prompt if there is any.
        /// Calling it after appending the prompt.
        let beforeModelCallResult = await self.beforeModelCall()

        switch beforeModelCallResult {
        case .cancelled(let response):
            /// prompt and response already added to the history. simply set the result here
            /// **Not** returning early because `afterModelCall` will need to be called since `beforeModelCall` is already called.
            modelStopData = .init(
                response: response,
                invocationState: invocationState,
                usage: .zero
            )
        case .continue:
            do {
                if let continuation {
                    for try await snapshot in session.streamResponse(
                        to: "",
                        metadata: dummyPromptMetadata
                    ) {
                        /// Always calculate the usage instead of using response.usage
                        /// because `snapshot.usage` sometimes does not reflect the full usage of this invoke
                        continuation.yield(
                            .init(
                                rawContent: snapshot.rawContent,
                                usage: calculateUsageDiff(
                                    before: beforeCallUsage,
                                    after: session.usage
                                )
                            )
                        )
                    }
                } else {
                    let _ = try await session.respond(
                        to: "",
                        metadata: dummyPromptMetadata
                    )
                }

                let entry: Transcript.Response =
                    self.session.lastResponse
                    ?? .init(segments: [.text(.init(content: ""))])

                /// Always calculate the usage instead of using response.usage
                /// because `response.usage` sometimes does not reflect the full usage of this invoke
                modelStopData = ModelStopData(
                    response: entry,
                    invocationState: invocationState,
                    usage: calculateUsageDiff(
                        before: beforeCallUsage,
                        after: session.usage
                    )
                )
            } catch {
                let usage = calculateUsageDiff(
                    before: beforeCallUsage,
                    after: session.usage
                )
                if let error = error.toolCallsReceived {
                    modelStopData = ModelStopData(
                        toolCalls: error.toolCalls,
                        invocationState: invocationState,
                        usage: usage
                    )

                } else {
                    modelStopData = ModelStopData(
                        error: error,
                        invocationState: invocationState,
                        usage: usage
                    )
                }
            }
        }

        continuation?.yield(.modelStop(modelStopData))

        let afterModelCallResult = await self.afterModelCall(
            stopData: modelStopData,
            currentAttempt: currentAttempt
        )

        switch afterModelCallResult {
        case .retry:
            if let prompt {
                /// technically speaking, the else branch should return the same thing. But with the id, it is more guaranteed in case the history is modified somewhere else.
                self.history = self.history.prefix(while: {
                    $0.id != prompt.id
                })
            } else {
                if let lastIndex = self.history.lastIndex(where: {
                    $0.asPrompt != nil
                }) {
                    self.history = self.history.prefix(upTo: lastIndex)
                }
            }
            return await invokeModel(
                prompt: prompt,
                currentAttempt: currentAttempt + 1,
                session: session,
                streamingInto: continuation
            )
        case .continue(let updatedReason):
            modelStopData = ModelStopData(
                stopReason: updatedReason,
                invocationState: modelStopData.invocationState,
                usage: modelStopData.usage
            )
        }

        return modelStopData
    }

    private func calculateUsageDiff(
        before: LanguageModelSession.Usage,
        after: LanguageModelSession.Usage
    ) -> LanguageModelSession.Usage {
        return LanguageModelSession.Usage(
            input: .init(
                totalTokenCount: after.input.totalTokenCount
                    - before.input.totalTokenCount,
                cachedTokenCount: after.input.cachedTokenCount
                    - before.input.cachedTokenCount
            ),
            output: .init(
                totalTokenCount: after.output.totalTokenCount
                    - before.output.totalTokenCount,
                reasoningTokenCount: after.output.reasoningTokenCount
                    - before.output.reasoningTokenCount
            )
        )
    }

    private func generationOptionsForToolResponse(
        _ options: GenerationOptions
    ) -> GenerationOptions {
        var options = options
        /// Make sure the `toolCallingMode` is not `required` to avoid an infinite tool-calling loop (which is one of the FoundationModels SDK bug as of 2026.10.12)
        if options.toolCallingMode == .required {
            options.toolCallingMode = .allowed
        }
        return options
    }

    private var dummyPromptMetadata: [String: any ConvertibleToGeneratedContent]
    {
        [InternalMetadataKey.dummyPrompt: true]
    }

    /// Produces a response stream to a prompt.
    ///
    /// - Parameters:
    ///   - prompt: A prompt for the model to respond to.
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    ///   - toolExecutionMode: Strategy for executing tool calls that the model emits in a single assistant turn.
    ///
    /// Passing nil for parameters other than `prompt` to use the `defaultInvocationOptions`.
    public func streamResponse(
        to prompt: String,
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
    ) -> AsyncStream<AgentStreamEvent> {
        return self.streamResponse(
            to: Prompt(prompt),
            schema: schema,
            options: options,
            metadata: metadata,
            contextOptions: contextOptions,
            invocationState: invocationState,
            toolExecutionMode: toolExecutionMode
        )
    }

    /// Produces a response stream to a prompt.
    ///
    /// - Parameters:
    ///   - prompt: A prompt for the model to respond to.
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    ///   - toolExecutionMode: Strategy for executing tool calls that the model emits in a single assistant turn.
    ///
    /// Passing nil for parameters other than `prompt` to use the `defaultInvocationOptions`.
    public func streamResponse(
        to prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions? = nil,
        metadata: [String: any ConvertibleToGeneratedContent]? = nil,
        contextOptions: ContextOptions? = nil,
        invocationState: InvocationState? = nil,
        toolExecutionMode: ToolExecutionMode? = nil,
    ) -> AsyncStream<AgentStreamEvent> {
        let resolvedOptions = buildInvocationOptions(
            schema: schema,
            options: options,
            metadata: metadata,
            contextOptions: contextOptions,
            invocationState: invocationState,
            toolExecutionMode: toolExecutionMode
        )

        let schema = resolvedOptions.schema
        let options = resolvedOptions.options
        let metadata = resolvedOptions.metadata
        let contextOptions = resolvedOptions.contextOptions
        let invocationState = resolvedOptions.invocationState
        let toolExecutionMode = resolvedOptions.toolExecutionMode

        self.resetInvocationState()
        self.invocationState = invocationState

        /// Important:
        /// This function is the **only** place to call `continuation.finish` to ensure the `afterInvocation` is handled correctly.
        /// **Never** call `continuation.finish` on child functions
        return AsyncStream<AgentStreamEvent> { continuation in
            // Required to convert ConvertibleToGeneratedContent to GeneratedContent to avoid the following concurrency error:
            // Passing closure as a 'sending' parameter risks causing data races between code in the current isolation context and concurrent execution of the closure
            let metadata = metadata.mapValues(\.generatedContent)

            Task {
                [
                    prompt, schema, options, metadata, contextOptions,
                    invocationState,
                    session, runInvocation, toolExecutionMode
                ] in

                let _ = await runInvocation(
                    Prompt(prompt),
                    schema,
                    options,
                    metadata,
                    contextOptions,
                    invocationState,
                    toolExecutionMode,
                    1,
                    session,
                    continuation
                )

                continuation.finish()
            }
        }
    }
}

/// Strategy for executing tool calls that the model emits in a single assistant turn.
/// - `parallel`: runs all tool calls from a single turn in parallel.
/// - `sequential`: runs tool calls one at a time
public enum ToolExecutionMode: Sendable, Equatable, Hashable {
    case sequential
    case parallel
}

public struct ToolCallResult: Sendable {
    public let toolCall: Transcript.ToolCall

    /// The error here, if present, will be penetrate to the `AgentResult` directly as `AgentStopReason.ToolCallError`
    public let result: Result<Transcript.ToolOutput, Error>
}

extension Agent {

    private func callTools(
        _ toolCalls: Transcript.ToolCalls,
        mode: ToolExecutionMode,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    )
        async -> AfterToolsEventHandler.CallbackHandlingResult
    {
        let results: [ToolCallResult]

        /// no need to stream the toolCalls before the hook callback here
        /// because it is already streamed as a model stop
        let beforeToolResult = await self.beforeTools(toolCalls: toolCalls)

        switch beforeToolResult {

        case .cancelled(let outputs):
            results = outputs.map { call, output in
                .init(toolCall: call, result: .success(output))
            }
        case .continue:
            switch mode {
            case .sequential:
                results = await callToolSequential(
                    toolCalls,
                    streamingInto: continuation
                )
            case .parallel:
                results = await callToolsParallel(
                    toolCalls,
                    streamingInto: continuation
                )
            }
        }

        /// update the last `Transcript.ToolCalls` in the history to handle any tool call update within the `BeforeToolCall` hook callback
        if let index = self.history.lastIndex(where: {
            $0.id == toolCalls.id
        }) {
            self.history[index] = .toolCalls(
                Transcript.ToolCalls(id: toolCalls.id, results.map(\.toolCall))
            )
        }

        return await self.afterTools(toolCallResults: results)
    }

    private func callToolsParallel(
        _ toolCalls: Transcript.ToolCalls,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async -> [ToolCallResult] {

        let results = await withTaskGroup(of: ToolCallResult.self) { group in
            var results: [ToolCallResult] = []

            for toolCall in toolCalls {
                group.addTask { [callTool] in
                    return await callTool(
                        toolCall,
                        toolCalls,
                        1,
                        continuation
                    )
                }
            }

            for await result in group {
                results.append(result)
            }

            return results
        }

        return results
    }

    private func callToolSequential(
        _ toolCalls: Transcript.ToolCalls,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    )
        async -> [ToolCallResult]
    {
        var output: [ToolCallResult] = []
        for toolCall in toolCalls {
            let result = await callTool(
                for: toolCall,
                currentCalls: toolCalls,
                currentAttempt: 1,
                streamingInto: continuation
            )
            output.append(result)
        }
        return output
    }

    private func callTool(
        for toolCall: Transcript.ToolCall,
        currentCalls: Transcript.ToolCalls,
        currentAttempt: Int,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?,
    ) async
        -> ToolCallResult
    {
        /// streaming event coming *before* hooks
        /// Pro: immediate feed back instead of waiting for all hooks to finish
        /// Con: in case the input is transformed in the hook, what user sees could be different to what is actually added to the session
        continuation?.yield(.init(toolCall: toolCall))

        let beforeCallResult = await self.beforeToolCall(
            toolCall,
            allCalls: currentCalls
        )

        var toolCall = toolCall
        var result: ToolCallResult

        switch beforeCallResult {
        case .cancelled(let toolOutput):
            result = .init(toolCall: toolCall, result: .success(toolOutput))
        case .continue(let updatedCall):
            toolCall = updatedCall
            do {
                let toolOutput: any PromptRepresentable
                let schemaName: String
                if let tool = getTool(with: updatedCall.toolName) {
                    toolOutput = try await tool.call(
                        arguments: updatedCall.arguments
                    ).output
                    schemaName = tool.parameters.name
                } else {
                    let toolNotFound = ToolOutputWrapper(
                        missingTool: updatedCall.toolName
                    )
                    toolOutput = toolNotFound.promptRepresentation
                    schemaName = "GeneratedContent"
                }

                let outputTranscript = await Transcript.ToolOutput(
                    id: updatedCall.id,
                    toolName: updatedCall.toolName,
                    segments: self.toolOutputSegments(
                        from: toolOutput,
                        schemaName: schemaName
                    )
                )

                result = .init(
                    toolCall: updatedCall,
                    result: .success(outputTranscript)
                )
            } catch {
                result = .init(
                    toolCall: updatedCall,
                    result: .failure(
                        ToolCallError(toolCall: updatedCall, error: error)
                    )
                )
            }
        }

        /// streaming event coming *before* hooks
        /// Pro: immediate feed back instead of waiting for all hooks to finish
        /// Con: in case the output is transformed in the hook, what user sees could be different to what is actually added to the session
        continuation?.yield(.init(toolResult: result.result))

        let afterToolResult = await self.afterToolCall(
            result: result,
            currentAttempt: currentAttempt
        )

        switch afterToolResult {
        case .retry:
            /// no history modified yet in the call therefore no need to roll back
            /// return the retry directly.
            return await self.callTool(
                for: toolCall,
                currentCalls: currentCalls,
                currentAttempt: currentAttempt + 1,
                streamingInto: continuation
            )
        case .continue(let updatedResult):
            switch updatedResult {
            case .success(var updatedSuccess):
                /// make sure the id and name is correct as the pairing is required by the framework
                updatedSuccess.id = toolCall.id
                updatedSuccess.toolName = toolCall.toolName
                result = .init(
                    toolCall: toolCall,
                    result: .success(updatedSuccess)
                )
            case .failure(let error):
                result = .init(
                    toolCall: toolCall,
                    result: .failure(error)
                )
            }
        }

        /// Adding to history after the hooks to handle possible transformations
        if let success = try? result.result.get() {
            self.history.append(.toolOutput(success))
        }

        return result
    }
}

extension LanguageModelSession.Usage {
    static let zero: LanguageModelSession.Usage = LanguageModelSession.Usage(
        input: .init(totalTokenCount: 0, cachedTokenCount: 0),
        output: .init(totalTokenCount: 0, reasoningTokenCount: 0)
    )
}

// MARK: - Hook
extension Agent {
    private func beforeToolCall(
        _ toolCall: Transcript.ToolCall,
        allCalls: Transcript.ToolCalls
    ) async -> BeforeToolCallEventHandler.CallbackHandlingResult {
        print(#function)
        let handlers = hookRegistry.beforeToolCallHandlers
        var event = BeforeToolCallEventHandler.EventPayload(
            toolCall: toolCall,
            toolCalls: Array(allCalls),
            agent: agentSnapshot
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Tool call cancelled with a cancelled content. last-wins.
        if let cancel = event.cancel {
            let toolOutput = ToolOutputWrapper(cancel, status: .error)
            let outputTranscript = Transcript.ToolOutput(
                id: toolCall.id,
                toolName: toolCall.toolName,
                segments: toolOutput.segments
            )

            /// Not add the output entry to the history yet.
            /// The output will be added after `afterToolCall` to handle any mutation

            return .cancelled(outputTranscript)
        }

        /// Not changing the toolCalls in the history yet here but wait for all tool calls to finish to batch update
        return .continue(event.toolCall)
    }

    private func afterToolCall(result: ToolCallResult, currentAttempt: Int)
        async -> AfterToolCallEventHandler.CallbackHandlingResult
    {
        print(#function)

        let handlers = hookRegistry.afterToolCallHandlers
        var event = AfterToolCallEventHandler.EventPayload(
            toolCall: result.toolCall,
            toolResult: result.result,
            agent: agentSnapshot,
            attemptCount: currentAttempt
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        if event.retry {
            return .retry
        }

        return .continue(event.toolResult)

    }

    private func beforeTools(toolCalls: Transcript.ToolCalls) async
        -> BeforeToolsEventHandler.CallbackHandlingResult
    {
        print(#function)

        let handlers = hookRegistry.beforeToolsHandlers
        var event = BeforeToolsEventHandler.EventPayload(
            toolCalls: Array(toolCalls),
            agent: agentSnapshot
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// All Tool calls cancelled with a cancelled content. last-wins.
        /// `Transcript.ToolCalls` is already in the history so there is no need to add it.
        if let cancel = event.cancel {
            let toolOutput = ToolOutputWrapper(cancel, status: .error)
            let outputTranscripts = toolCalls.map { toolCall in
                return (
                    toolCall,
                    Transcript.ToolOutput(
                        id: toolCall.id,
                        toolName: toolCall.toolName,
                        segments: toolOutput.segments
                    )
                )
            }

            /// Add the response entry to the history.
            ///
            /// Doing this before calling the `handleOnResponse` because
            /// the when `onResponse` is triggered by the system,
            /// the `history` will contains the last `Transcript.Response`
            self.history.append(
                contentsOf: outputTranscripts.map(\.1).map(
                    Transcript.Entry.toolOutput
                )
            )

            return .cancelled(outputTranscripts)
        }

        return .continue

    }

    private func afterTools(toolCallResults: [ToolCallResult]) async
        -> AfterToolsEventHandler.CallbackHandlingResult
    {
        print(#function)

        let handlers = hookRegistry.afterToolsHandlers
        var event = AfterToolsEventHandler.EventPayload(
            toolResults: toolCallResults,
            agent: agentSnapshot
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        if let endTurn = event.endTurn {
            /// wrap any `ToolCallResult.output.failure` with `ToolOutputWrapper` and add to history.
            for result in toolCallResults {
                switch result.result {
                case .success(_):
                    continue
                case .failure(let error):
                    let wrapper = ToolOutputWrapper(error)
                    let toolCall = result.toolCall
                    let outputTranscript = Transcript.ToolOutput(
                        id: toolCall.id,
                        toolName: toolCall.toolName,
                        segments: wrapper.segments
                    )
                    /// add to history
                    self.history.append(.toolOutput(outputTranscript))
                }
            }

            /// programmatically append `endTurn` as model response to history
            let response = Transcript.Response(
                segments: SegmentBuilder.segments(
                    from: endTurn,
                    schemaName: "GeneratedContent"
                )
            )

            self.history.append(.response(response))

            return .endTurn(response)
        }

        return .continue(toolCallResults)

    }

    private func beforeInvocation(prompt: Transcript.Prompt) async
        -> BeforeInvocationEventHandler.CallbackHandlingResult
    {
        print(#function)

        /// history will *not* contain the prompt as its last entry
        let handlers = hookRegistry.beforeInvocationHandlers
        var event = BeforeInvocationEventHandler.EventPayload(
            prompt: prompt,
            agent: agentSnapshot
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Invocation cancelled with a cancelled content. last-wins.
        /// No `BeforeModelCall` opens, therefore there is no need to trigger `AfterModelCall` here.
        if let cancel = event.cancel {
            /// Add in the final prompt. Last-wins
            self.history = history + [.prompt(event.prompt)]

            let response = Transcript.Response(
                segments: SegmentBuilder.segments(
                    from: cancel,
                    schemaName: "GeneratedContent"
                )
            )

            /// Add the response entry to the history.
            ///
            /// No need to call `afterModelCall` here for clean-up because `beforeModelCall` is never called.
            self.history.append(.response(response))

            return .cancelled(response)
        }

        return .continue(event.prompt)
    }

    private func beforeModelCall() async
        -> BeforeModelCallEventHandler.CallbackHandlingResult
    {
        print(#function)

        let handlers = hookRegistry.beforeModelCallHandlers
        var event = BeforeModelCallEventHandler.EventPayload(
            agent: agentSnapshot
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Model call cancelled with a cancelled content. last-wins.
        /// Prompt is already in the history so there is no need to add it.
        if let cancel = event.cancel {
            let response = Transcript.Response(
                segments: SegmentBuilder.segments(
                    from: cancel,
                    schemaName: "GeneratedContent"
                )
            )

            /// Add the response entry to the history.
            ///
            /// Doing this before calling the `handleOnResponse` because
            /// the when `onResponse` is triggered by the system,
            /// the `history` will contains the last `Transcript.Response`
            self.history.append(.response(response))

            return .cancelled(response)
        }

        return .continue
    }

    private func afterModelCall(stopData: ModelStopData, currentAttempt: Int)
        async -> AfterModelCallEventHandler.CallbackHandlingResult
    {
        print(#function)

        /// remove the last entry from the history
        var lastEntryId: Transcript.Entry.ID? = nil
        switch stopData.stopReason {
        case .endTurn(let response):
            lastEntryId = response.id
        case .toolUse(let toolCalls):
            lastEntryId = toolCalls.id
        default:
            break
        }

        if let lastEntryId {
            self.history.removeAll(where: { $0.id == lastEntryId })
        }

        let handlers = hookRegistry.afterModelCallHandlers
        var event = AfterModelCallEventHandler.EventPayload(
            stopReason: stopData.stopReason,
            usage: stopData.usage,
            agent: agentSnapshot,
            attemptCount: currentAttempt
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Invocation retry requested. last-wins. Take priority over `resume`
        if event.retry {
            return .retry
        }

        /// update the history with the new stop reason
        switch event.stopReason {
        case .endTurn(let response):
            self.history.append(.response(response))
        case .toolUse(let toolCalls):
            self.history.append(.toolCalls(toolCalls))
        default: break
        }

        return .continue(event.stopReason)

    }

    private func afterInvocation(
        result: AgentResult,
        currentAttempt: Int
    ) async
        -> AfterInvocationEventHandler.CallbackHandlingResult
    {
        print(#function)
        /// history will *not* contain the prompt as its last entry
        let handlers = hookRegistry.afterInvocationHandlers
        var event = AfterInvocationEventHandler.EventPayload(
            result: result,
            agent: agentSnapshot,
            attemptCount: currentAttempt
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Invocation retry requested. last-wins. Take priority over `resume`
        if event.retry {
            return .retry
        }

        /// Invocation resume with a new prompt.
        if let resume = event.resume {
            return .resume(resume)
        }

        return .finish
    }

    private func getTool(with name: String)
        -> InvocableTool?
    {
        return self.tools.first(where: {
            $0.invocableTool.name == name
        })?.invocableTool
    }

    var agentSnapshot: AgentSnapshot {
        AgentSnapshot(
            session: self.session,
            history: history
        )
    }

    func toolOutputSegments<Output: PromptRepresentable>(
        from output: Output,
        schemaName: String
    ) async -> [Transcript.Segment] {
        let segments = await SegmentBuilder.segments(
            from: output.promptRepresentation
        )
        if segments.isEmpty {
            if let generatedContent = output as? ConvertibleToGeneratedContent {
                return SegmentBuilder.segments(
                    from: GeneratedContent(generatedContent),
                    schemaName: schemaName
                )
            }
            return [Transcript.Segment.text(.init(content: "\(output)"))]
        }

        return segments
    }
}

extension Transcript.Entry {
    var asToolOutput: Transcript.ToolOutput? {
        if case .toolOutput(let output) = self {
            return output
        }
        return nil
    }

    var asResponse: Transcript.Response? {
        if case .response(let response) = self {
            return response
        }
        return nil
    }

    var asToolCalls: Transcript.ToolCalls? {
        if case .toolCalls(let calls) = self {
            return calls
        }
        return nil
    }

    var asPrompt: Transcript.Prompt? {
        if case .prompt(let value) = self {
            return value
        }
        return nil
    }

    var asInstruction: Transcript.Instructions? {
        if case .instructions(let value) = self {
            return value
        }
        return nil
    }
}

extension LanguageModelSession {
    var lastResponse: Transcript.Response? {
        self.transcript.history.compactMap {
            $0.asResponse
        }.last
    }
}

extension Error {

    var toolCallsReceived: ToolCallsReceived? {
        return self.error(ToolCallsReceived.self)
    }

    func isError<T: Error>(_ type: T.Type) -> Bool {
        return self.error(type) != nil
    }

    func error<T: Error>(_ type: T.Type) -> T? {
        if let error = self as? T {
            return error
        }

        if let error = self as? LanguageModelSession.ToolCallError {
            return error.underlyingError.error(type)
        }
        return nil
    }
}
