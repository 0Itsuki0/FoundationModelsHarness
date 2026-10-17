//
//  Agent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import SwiftUI

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

    @SessionPropertyEntry
    var hookRegistry: HookRegistry = .init()
}

public typealias InvocationState = [String: JSONValue]
public typealias AgentState = [String: JSONValue]

// TODO: - add invocation options in and add a default invocation option on Agent `init`.
public struct InvocationOptions: Sendable {}

extension Agent {
    public subscript<T>(dynamicMember keyPath: KeyPath<LanguageModelSession, T>)
        -> T
    {
        return self.session[keyPath: keyPath]
    }
}

extension Transcript.Prompt {
    static let dummyPrompt = Transcript.Prompt(
        metadata: [InternalMetadataKey.dummyPrompt: true],
        segments: [],
    )
}

@dynamicMemberLookup
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

    public private(set) var history: Transcript.HistoryView {
        get {
            session.transcript.history
        }
        set {
            session.transcript.history = newValue
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
        get {
            session.properties.hookRegistry
        }
        set {
            session.properties.hookRegistry = newValue
        }
    }

    private let tools: [ToolConfig]
    private var delegatedToolName: [String] {
        self.tools.filter({ $0.delegate }).map(\.invocableTool.name)
    }

    private func isDelegatedTool(_ toolName: String) -> Bool {
        self.delegatedToolName.contains(toolName)
    }

    private let profile: AgentProfile

    public init(tools: [ToolConfig], instruction: Instructions) {
        let instruction = ToolConfig.injectDelegationPrompt(
            for: tools,
            on: instruction
        )
        let profile = AgentProfile(tools: tools, instruction: instruction)
        self.profile = profile
        let session = LanguageModelSession(profile: profile)
        self.session = session
        self.tools = tools
        self.setupBuiltInHooks()
    }

    private func setupBuiltInHooks() {
        self.addHook(
            AfterToolCallEventHandler(
                callback: { [weak self] event in
                    guard let self else { return }
                    if isDelegatedTool(event.toolCall.toolName) {
                        event.endTurn = try? JSONValue(
                            event.toolOutput.segments.rawGeneratedContent
                        )
                        return
                    }
                },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            )
        )
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
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    ///   - toolExecutionMode: Strategy for executing tool calls that the model emits in a single assistant turn.
    @discardableResult
    public func respond(
        to prompt: String,
        schema: GenerationSchema? = nil,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
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
    ///   - metadata: Metadata provided as part of this prompt.
    ///   - options: Options that control how tokens are sampled from the distribution the model produces.
    ///   - responseFormat: A response format that describes the output structure.
    ///   - contextOptions: Settings that configure how the model is prompted.
    ///   - invocationState: Per-invocation state. Passed to lifecycle hook events and tools, and returned on `AgentResult.invocationState`. Mutable — hooks and tools may read and write
    @discardableResult
    public func respond(
        to prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
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

    /// One-Invocation wrapper.
    @discardableResult
    private func runInvocation(
        on prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode,
        currentAttempt: Int,
        session: LanguageModelSession,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async -> AgentResult {
        self.resetInvocationState()
        self.invocationState = invocationState

        var promptTranscript = await Transcript.Prompt(
            metadata: metadata,
            segments: SegmentBuilder.segments(from: prompt),
            options: options,
            responseFormat: schema.map {
                Transcript.ResponseFormat(schema: $0)
            },
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

        let modelStopData: ModelStopData

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

                //                if let error = error.responseFinishError {
                //                    modelStopData = ModelStopData(
                //                        response: error.response,
                //                        invocationState: invocationState,
                //                        usage: usage
                //                    )
                //                } else
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
        case .continue:
            break
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

    public func streamResponse(
        to prompt: String,
        schema: GenerationSchema? = nil,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
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

    public func streamResponse(
        to prompt: Prompt,
        schema: GenerationSchema? = nil,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:],
        contextOptions: ContextOptions = ContextOptions(),
        invocationState: InvocationState = [:],
        toolExecutionMode: ToolExecutionMode = .parallel
    ) -> AsyncStream<AgentStreamEvent> {
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

        return await self.afterTools(toolCallResults: results)

        //        switch afterToolResult {
        //
        //        case .endTurn(_):
        //            <#code#>
        //        case .continue:
        //            <#code#>
        //        }
        //
        //        return results.map { result in
        //            result.result.mapError({
        //                ToolCallError(toolCall: result.toolCall, error: $0)
        //            })
        //        }
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
                    let result = await callTool(toolCall, continuation)
                    return ToolCallResult(toolCall: toolCall, result: result)
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
                streamingInto: continuation
            )
            output.append(.init(toolCall: toolCall, result: result))
        }
        return output
    }

    private func callTool(
        for toolCall: Transcript.ToolCall,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation?
    ) async
        -> Result<Transcript.ToolOutput, Error>
    {
        /// streaming event coming *before* hooks
        /// Pro: immediate feed back instead of waiting for all hooks to finish
        /// Con: in case the input is transformed in the hook, what user sees could be different to what is actually added to the session
        continuation?.yield(.init(toolCall: toolCall))

        await self.beforeToolCall()

        let result: Result<Transcript.ToolOutput, Error>

        do {

            let tool = try getTool(for: toolCall)

            let toolOutput = try await tool.call(
                arguments: toolCall.arguments
            )

            let outputTranscript = await Transcript.ToolOutput(
                id: toolCall.id,
                toolName: toolCall.toolName,
                segments: self.toolOutputSegments(
                    from: toolOutput,
                    schemaName: tool.parameters.name
                )
            )

            self.history.append(.toolOutput(outputTranscript))

            result = .success(outputTranscript)
        } catch {
            result = .failure(ToolCallError(toolCall: toolCall, error: error))
        }

        /// streaming event coming *before* hooks
        /// Pro: immediate feed back instead of waiting for all hooks to finish
        /// Con: in case the output is transformed in the hook, what user sees could be different to what is actually added to the session
        continuation?.yield(.init(toolResult: result))
        await self.afterToolCall()
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
        /// Prompt is already in the history so there is no need to add it.
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
            for (index, result) in toolCallResults.enumerated() {
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
            agent: createLocalAgent(with: history)
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
        let handlers = hookRegistry.afterModelCallHandlers
        var event = AfterModelCallEventHandler.EventPayload(
            stopData: stopData,
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

        return .continue

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

    private func beforeToolCall() async {
        print(#function)
    }

    private func afterToolCall() async {
        print(#function)
    }

    private func handleOnResponse(_ response: Transcript.Response) async throws
    {
        /// `history` will contains the last `Transcript.Response`

    }

    //    private func handleOnPrompt(_ prompt: Transcript.Prompt) async throws {
    //        /// remove the dummy empty prompt added when calling `responseStream`/`respond` used to force the retry from the updated history
    //        /// This will work as long as the transcript ends with prompt / tool output entry,
    //        /// which is indeed the case here.
    //        history.removeDummyPrompt()
    //
    //        /// Internal Retry. Return early. No Hook triggered.
    //        if isInternalRetry {
    //            return
    //        }
    //
    //        /// history will contain the prompt as its last entry
    //        ///
    //        /// NOTE: **Not** modifying history directly at the start
    //        /// so that in the case where handler throws
    //        /// we still have a clean history (managed by the FoundationModels SDK. Untouched)
    //        var historyBeforePrompt: Transcript.HistoryView = history
    //        historyBeforePrompt.removeAll {
    //            $0.asPrompt != nil && $0.id == prompt.id
    //        }
    //
    //        let handlers = hookRegistry.beforeInvocationHandlers
    //        var event = BeforeInvocationEventHandler.EventPayload(
    //            prompt: prompt,
    //            agent: createLocalAgent(with: historyBeforePrompt)
    //        )
    //
    //        for handler in handlers {
    //            try await handler.callback(&event)
    //        }
    //
    //        /// Model call cancelled with a cancelled content. last-wins.
    //        if let cancel = event.cancel {
    //            let response = Transcript.Response(
    //                segments: SegmentBuilder.segments(
    //                    from: cancel,
    //                    schemaName: "GeneratedContent"
    //                )
    //            )
    //
    //            /// Add the response entry to the history.
    //            ///
    //            /// Doing this before calling the `handleOnResponse` because
    //            /// the when `onResponse` is triggered by the system,
    //            /// the `history` will contains the last `Transcript.Response`
    //            self.history.append(.response(response))
    //
    //            /// programmatically triggers the `onResponse` Event
    //            try await self.handleOnResponse(response)
    //
    //            throw ResponseFinishedError(response)
    //        }
    //
    //        /// No changes to the tool Call. Return early.
    //        guard prompt != event.prompt else {
    //            return
    //        }
    //
    //        /// Prompt modified. Last-wins
    //        ///
    //        /// NOTE: modifying the history here directly will indeed effect what the model sees (respond to),
    //        /// which is different from modifying the tool call in onToolCall where the model will NOT see the updated tool call parameters.
    //        self.history = historyBeforePrompt + [.prompt(event.prompt)]
    //
    //    }

    private func handleOnToolOutput(
        toolCall: Transcript.ToolCall,
        toolOutput: Transcript.ToolOutput,
        attemptCount: Int = 1
    ) async throws {
        /// `history` will contains the last Transcript.ToolCalls entry but should **NOT** contain the `Transcript.ToolOutput`
        /// However, still do a defensive filtering here.
        var historyBeforeOutput = history
        historyBeforeOutput.removeAll {
            $0.asToolOutput != nil && $0.id == toolOutput.id
        }

        let handlers = hookRegistry.afterToolCallHandlers
        var event = AfterToolCallEventHandler.EventPayload(
            toolCall: toolCall,
            toolOutput: toolOutput,
            agent: createLocalAgent(with: historyBeforeOutput),
            attemptCount: max(1, attemptCount)
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        // TODO: - handle event.toolOutput change

        /// Retry Tool call. last-wins.
        if event.retry {
            return try await retryToolCall(toolCall, attemptCount: attemptCount)
        }

        /// Short-circuit to the output with the `endTurn` value
        if let endTurn = event.endTurn {
            /// programmatically append tool output to history
            self.history.append(.toolOutput(event.toolOutput))

            /// programmatically append `endTurn` as model response to history
            let response = Transcript.Response(
                segments: SegmentBuilder.segments(
                    from: endTurn,
                    schemaName: "GeneratedContent"
                )
            )
            self.history.append(.response(response))

            /// programmatically trigger `onResponse`
            try await self.handleOnResponse(response)

            /// throw `ResponseFinishedError` to break out of the agent loop
            throw ResponseFinishedError(response)
        }
    }

    private func retryToolCall(
        _ toolCall: Transcript.ToolCall,
        attemptCount: Int
    ) async throws {
        //        let tool = try getTool(for: toolCall)
        //
        //        /// **Programmatically** call the wrapper tool.
        //        let outputTranscript = try await callTool(for: toolCall, using: tool)
        //
        //        /// programmatically triggers the `onToolOutput` Event
        //        try await self.handleOnToolOutput(
        //            toolCall: toolCall,
        //            toolOutput: outputTranscript,
        //            attemptCount: attemptCount + 1
        //        )
    }

    /// Handle Tool calls on the Profile.
    private func handleOnToolCall(_ toolCall: Transcript.ToolCall) async throws
    {
        /// `history` will contains the last Transcript.ToolCalls entry
        /// (which contains the toolCall: Transcript.ToolCall as one of the calls)
        ///
        /// NOTE: **Not** modifying history directly at the start
        /// so that in the case where handler throws
        /// we still have a clean history (managed by the FoundationModels SDK. Untouched)
        let historyBeforeLastToolCall: Transcript.HistoryView
        /// extracted last tool calls event
        let lastToolCallsEvent: Transcript.ToolCalls

        if let lastHistory = history.last?.asToolCalls {
            historyBeforeLastToolCall = history.prefix(history.count - 1)
            lastToolCallsEvent = lastHistory
        } else {
            historyBeforeLastToolCall = history
            lastToolCallsEvent = .init([toolCall])
        }

        let calls = lastToolCallsEvent.expand()

        let handlers = hookRegistry.beforeToolCallHandlers
        var event = BeforeToolCallEventHandler.EventPayload(
            toolCall: toolCall,
            toolCalls: calls,
            agent: createLocalAgent(with: historyBeforeLastToolCall)
        )

        for handler in handlers {
            await handler.callback(&event)
        }

        /// Tool call cancelled with a cancelled content. last-wins.
        if let cancel = event.cancel {
            return try await handleToolCallCancelled(cancel, on: toolCall)
        }

        /// No changes to the tool Call. Return early.
        guard toolCall != event.toolCall else {
            return
        }

        /// Handle tool input / name changes. last-wins.
        try await self.handleToolCallUpdated(
            toolCalls: lastToolCallsEvent,
            previousId: toolCall.id,
            updated: event.toolCall,
            historyBeforeLastToolCall: historyBeforeLastToolCall
        )
    }

    /// Tool call cancelled
    private func handleToolCallCancelled(
        _ cancellationContent: JSONValue,
        on toolCall: Transcript.ToolCall
    )
        async throws
    {
        let toolOutput = ToolOutputWrapper(cancellationContent, status: .error)
        let outputTranscript = Transcript.ToolOutput(
            id: toolCall.id,
            toolName: toolCall.toolName,
            segments: toolOutput.segments
        )

        /// programmatically triggers the `onToolOutput` Event
        try await self.handleOnToolOutput(
            toolCall: toolCall,
            toolOutput: outputTranscript
        )

        /// Add in the tool output to the session's history
        ///
        /// NOTE: do this *after* the `handleOnToolOutput` because for the `onToolOutput` triggered by the system,
        /// the `history` will contains the last Transcript.ToolCalls entry but **NOT** the `Transcript.ToolOutput`
        self.history.append(
            .toolOutput(outputTranscript)
        )

        /// throw retry error to force the model to generate a response based on the tool output.
        throw RetryModelGenerationError.afterToolOutput
    }

    /// Tool call parameters (name, input argument, and etc) updated.
    ///
    /// Since updating the `history` in `onToolCall` will **only** reflected to the session history,
    /// aka:  effect what the model sees **On the next turn**.
    /// but not **NOT** effect the actual argument used to call the tool nor which tool is called.
    /// Therefore, we will be
    /// 1. manually calling the tool
    /// 2. append the tool output to the history
    /// 3. throw to terminate the current turn
    /// 4. retry the generation with the tool already outputted
    private func handleToolCallUpdated(
        toolCalls: Transcript.ToolCalls,
        previousId: Transcript.ToolCall.ID,
        updated toolCall: Transcript.ToolCall,
        historyBeforeLastToolCall: Transcript.HistoryView
    )
        async throws
    {
        /// since the `invocableTool` is a wrapper around the `tool` passing in, both share the same arguments, output, schema, name
        let tool = try getTool(for: toolCall)

        var calls = toolCalls.expand()

        /// update the target tool call
        if let index = calls.firstIndex(where: { $0.id == previousId }) {
            calls[index] = toolCall
        } else {
            calls.append(toolCall)
        }
        /// Add back the Transcript.ToolCalls and assign it to the history.
        //
        /// modifying the history here will effect what the model sees **On the next turn**.
        /// It will **NOT** effect the actual argument used to call the tool nor which tool is called.
        //
        /// NOTE: that we need to set `self.history` twice: once here, once after the `handleOnToolOutput`,
        /// because if one of the AfterToolCallEventHandler throws an error,
        /// we still want to record the updated tool call.
        self.history =
            historyBeforeLastToolCall + [
                .toolCalls(.init(id: toolCalls.id, calls))
            ]

        /// **Programmatically** call the wrapper tool if there is a change.
        ///
        /// This is needed because even if we have modified the session history with the new toolCall Parameter,
        /// (aka: history = historyTemp)
        /// the model will still use the previous tool name / arguments.
        let outputTranscript = try
            (await callTool(for: toolCall, streamingInto: nil)).get()

        /// programmatically triggers the `onToolOutput` Event
        try await self.handleOnToolOutput(
            toolCall: toolCall,
            toolOutput: outputTranscript
        )

        /// Add in the tool output to the session's history
        ///
        /// NOTE: do this *after* the `handleOnToolOutput` because for the `onToolOutput` triggered by the system,
        /// the `history` will contains the last Transcript.ToolCalls entry but **NOT** the `Transcript.ToolOutput`
        self.history.append(
            .toolOutput(outputTranscript)
        )

        /// throw retry error to force the model to generate a response based on the tool output.
        throw RetryModelGenerationError.afterToolOutput
    }

    private func getTool(for toolCall: Transcript.ToolCall) throws
        -> InvocableTool
    {
        guard
            let tool = self.tools.first(where: {
                $0.invocableTool.name == toolCall.toolName
            })?.invocableTool
        else {
            throw LanguageModelError.refusal(
                .init(
                    explanation: "Tool \(toolCall.toolName) is not registered.",
                    debugDescription:
                        "Register \(toolCall.toolName) and try again."
                )
            )
        }
        return tool
    }

    /// **Programmatically** call the wrapper tool
    //    private func callTool(
    //        for toolCall: Transcript.ToolCall,
    //        using tool: InvocableTool
    //    ) async throws
    //        -> Transcript.ToolOutput
    //    {
    //        let toolOutput = try await tool.call(
    //            arguments: toolCall.arguments
    //        )
    //
    //        let outputTranscript = await Transcript.ToolOutput(
    //            id: toolCall.id,
    //            toolName: toolCall.toolName,
    //            segments: self.toolOutputSegments(
    //                from: toolOutput,
    //                schemaName: tool.parameters.name
    //            )
    //        )
    //
    //        return outputTranscript
    //    }

    private func createLocalAgent(with history: Transcript.HistoryView)
        -> AgentSnapshot
    {
        return AgentSnapshot(
            session: self.session,
            history: history
        )
    }

    var agentSnapshot: AgentSnapshot {
        AgentSnapshot(
            session: self.session,
            history: history
        )
    }

    func toolOutputSegments(
        from output: InvocableTool.Output,
        schemaName: String
    ) async -> [Transcript.Segment] {
        let output = output.output
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
    var isRetryError: Bool {
        return self.isError(RetryModelGenerationError.self)
    }

    var retryError: RetryModelGenerationError? {
        return self.error(RetryModelGenerationError.self)
    }

    var toolCallsReceived: ToolCallsReceived? {
        return self.error(ToolCallsReceived.self)
    }

    //    var responseFinishError: ResponseFinishedError? {
    //        return self.error(ResponseFinishedError.self)
    //    }

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
