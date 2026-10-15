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

    @SessionPropertyEntry
    var isInternalRetry: Bool = false
}

public typealias InvocationState = [String: JSONValue]
public typealias AgentState = [String: JSONValue]

extension Agent {
    public subscript<T>(dynamicMember keyPath: KeyPath<LanguageModelSession, T>)
        -> T
    {
        return self.session[keyPath: keyPath]
    }
}

@dynamicMemberLookup
@Observable
public final class Agent: Sendable {

    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    var agentState: AgentState {
        get {
            session.properties.agentState
        }
        set {
            session.properties.agentState = newValue
        }
    }

    var history: Transcript.HistoryView {
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

    private var isInternalRetry: Bool {
        get {
            session.properties.isInternalRetry
        }
        set {
            session.properties.isInternalRetry = newValue
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
        // TODO: - maybe changed this to use `endTurn` instead so that `AfterInvocation` hooks can be triggered
        self.addHook(
            AfterToolCallEventHandler(
                callback: { [weak self] event in
                    guard let self else { return }
                    if isDelegatedTool(event.toolCall.toolName) {
                        event.endTurn = try JSONValue(
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

    // TODO: - add in wrappers for other respond / streamResponse methods

    @discardableResult
    public func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) async -> AgentResult {
        self.isInternalRetry = false
        self.resetInvocationState()

        defer {
            do {
                try await self.afterInvocation()
            } catch {

            }

            self.resetInvocationState()
        }

        do {
            try await self.beforeInvocation()
        } catch {

        }

        let agentResult: AgentResult = await agentLoop(
            to: prompt,
            options: options,
            metadata: metadata
        )

        print("agent result: ", agentResult)
        return agentResult
    }

    private func agentLoop(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) async -> AgentResult {
        let beforeCallUsage = session.usage

        var modelStopData = await invokeModel(
            to: prompt,
            options: options,
            metadata: metadata
        )

        var agentResult: AgentResult?

        agentLoop: while agentResult == nil {
            let usage = calculateUsageDiff(
                before: beforeCallUsage,
                after: session.usage
            )

            switch modelStopData.stopReason {

            case .endTurn(let response):
                agentResult = AgentResult(
                    response: response,
                    invocationState: invocationState,
                    usage: usage
                )
                break agentLoop
            case .refusal(let error):
                agentResult = AgentResult(
                    error: error,
                    invocationState: invocationState,
                    usage: usage
                )
                break agentLoop
            case .toolUse(let toolCall):
                do {
                    try await self.beforeToolCall()

                    let tool = try getTool(for: toolCall)
                    let toolOutput = try await self.callTool(
                        for: toolCall,
                        using: tool
                    )

                    try await self.afterToolCall()

                    self.history.append(
                        .toolOutput(toolOutput)
                    )

                    modelStopData = await self.invokeModel(
                        to: "",
                        options: options,
                        // buildRetryGenerationOptions(options, for: error),
                        metadata: buildRetryMetadata(metadata)
                    )

                    continue
                } catch {
                    agentResult = AgentResult(
                        error: error,
                        invocationState: invocationState,
                        usage: usage
                    )

                    break agentLoop
                }
            }
        }

        return agentResult!
    }

    private func invokeModel(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) async -> ModelStopData {

        let beforeCallUsage = session.usage

        do {
            try await self.beforeModelCall()
        } catch {

        }

        defer {
            do {
                try await self.afterModelCall()
            } catch {

            }

        }

        let modelStopData: ModelStopData

        do {
            let response = try await session.respond(
                to: prompt,
                metadata: metadata
            )
            let entry: Transcript.Response =
                self.session.lastResponse
                ?? .init(segments: [.text(.init(content: response.content))])

            //            return AgentResult(
            //                stopReason: .endTurn,
            //                lastMessage: entry,
            //                invocationState: invocationState,
            //                usage: calculateTurnUsage(
            //                    before: beforeCallUsage,
            //                    after: session.usage
            //                )
            //            )
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

            if let error = error.responseFinishError {
                /// history already contains the response. returning it directly.
                modelStopData = ModelStopData(
                    response: error.response,
                    invocationState: invocationState,
                    usage: usage
                )
            }

            else if let error = error.retryError {
                return await retry(
                    for: error,
                    options: options,
                    metadata: metadata
                )

            } else if let error = error.toolCallError {
                modelStopData = ModelStopData(
                    toolCall: error.toolCall,
                    invocationState: invocationState,
                    usage: usage
                )

            } else {

                //            return AgentResult(
                //                stopReason: .refusal,
                //                lastMessage: .init(segments: []),
                //                invocationState: invocationState,
                //                usage: usage
                //            )
                modelStopData = ModelStopData(
                    error: error,
                    invocationState: invocationState,
                    usage: usage
                )
            }
        }

        return modelStopData
    }

    private func retry(
        for error: RetryModelGenerationError,
        options: GenerationOptions,
        metadata: [String: any ConvertibleToGeneratedContent],
    ) async -> ModelStopData {
        self.isInternalRetry = true
        defer {
            self.isInternalRetry = false
        }

        // A dummy empty prompt in order to force the retry from the current history
        // the dummy will be removed from the history within `AgentProfile.onPrompt`
        return await self.invokeModel(
            to: "",
            options: buildRetryGenerationOptions(options, for: error),
            metadata: buildRetryMetadata(metadata)
        )
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

    /// Update tool calling mode based on the error to avoid infinite looping
    private func buildRetryGenerationOptions(
        _ options: GenerationOptions,
        for error: RetryModelGenerationError
    ) -> GenerationOptions {
        var options = options
        switch error {
        case .afterToolOutput:
            /// Make sure the `toolCallingMode` is not `required` to avoid an infinite tool-calling loop (which is one of the FoundationModels SDK bug as of 2026.10.12)
            if options.toolCallingMode == .required {
                options.toolCallingMode = .allowed
            }
        }
        return options
    }

    private func buildRetryMetadata(
        _ metadata: [String: any ConvertibleToGeneratedContent]
    ) -> [String: any ConvertibleToGeneratedContent] {
        var metadata = metadata
        metadata[InternalMetadataKey.dummyPrompt] = true
        return metadata
    }

    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) -> AsyncStream<AgentStreamEvent> {
        self.isInternalRetry = false
        self.resetInvocationState()

        return AsyncStream<AgentStreamEvent> { continuation in
            // Required to convert ConvertibleToGeneratedContent to GeneratedContent to avoid the following concurrency error:
            // Passing closure as a 'sending' parameter risks causing data races between code in the current isolation context and concurrent execution of the closure
            let metadata = metadata.mapValues(\.generatedContent)

            Task {
                [
                    session, resetInvocationState, metadata, beforeInvocation,
                    afterInvocation
                ] in
                do {
                    try await beforeInvocation()
                } catch {

                }

                defer {
                    do {
                        try await afterInvocation()
                    } catch {

                    }

                    resetInvocationState()
                }

                await invokeModelStream(
                    prompt: prompt,
                    metadata: metadata,
                    session: session,
                    streamingInto: continuation,
                )

                continuation.finish()
            }
        }
    }

    private func retryStream(
        for error: RetryModelGenerationError,
        options: GenerationOptions,
        metadata: [String: any ConvertibleToGeneratedContent],
        session: LanguageModelSession,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation
    ) async {
        self.isInternalRetry = true
        defer {
            self.isInternalRetry = false
        }

        let metadata = buildRetryMetadata(metadata)

        // A dummy empty prompt in order to force the retry from the current history
        // the dummy will be removed from the history within `AgentProfile.onPrompt`
        await self.invokeModelStream(
            prompt: "",
            options: buildRetryGenerationOptions(options, for: error),
            metadata: buildRetryMetadata(metadata),
            session: session,
            streamingInto: continuation
        )
    }

    private func invokeModelStream(
        prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent],
        session: LanguageModelSession,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation
    ) async {
        let beforeCallUsage = session.usage

        do {
            try await self.beforeModelCall()
        } catch {

        }

        do {
            for try await snapshot in session.streamResponse(
                to: prompt,
                metadata: metadata
            ) {
                /// the `calculateTurnUsage` is essentially the same as `snapshot.usage`in this case
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

            do {
                try await self.afterModelCall()
            } catch {

            }

            return

        } catch {
            do {
                try await self.afterModelCall()
            } catch {

            }

            let usage = calculateUsageDiff(
                before: beforeCallUsage,
                after: session.usage
            )

            if let error = error.responseFinishError {
                /// `history` already contains the response. Don't need to add anything.
                continuation.yield(
                    .init(
                        rawContent: error.response.segments.rawGeneratedContent,
                        usage: usage
                    )
                )
                return
            }

            if let error = error.retryError {
                await retryStream(
                    for: error,
                    options: options,
                    metadata: metadata,
                    session: session,
                    streamingInto: continuation
                )
                return
            }

            if let error = error.toolCallError {
                continuation.yield(
                    .init(toolCall: error.toolCall, usage: usage)
                )
                await streamToolCall(
                    toolCall: error.toolCall,
                    streamingInto: continuation,
                    invokeModelStream: {
                        await invokeModelStream(
                            prompt: "",
                            options: options,
                            metadata: buildRetryMetadata(metadata),
                            session: session,
                            streamingInto: continuation
                        )
                    }
                )
                return
            }

            continuation.yield(
                .init(error: error, usage: usage)
            )

            return
        }
    }

    private func streamToolCall(
        toolCall: Transcript.ToolCall,
        streamingInto continuation: AsyncStream<AgentStreamEvent>
            .Continuation,
        invokeModelStream: () async -> Void,
    ) async {
        /// Calling tool programmatically does not use any tokens.
        let toolCallUsage = LanguageModelSession.Usage.zero

        do {
            try await self.beforeToolCall()

            let tool = try getTool(for: toolCall)
            let toolOutput = try await self.callTool(
                for: toolCall,
                using: tool
            )

            try await self.afterToolCall()

            self.history.append(
                .toolOutput(toolOutput)
            )

            continuation.yield(
                .init(
                    toolOutput: toolOutput,
                    usage: toolCallUsage
                )
            )

            await invokeModelStream()

            return
        } catch {
            continuation.yield(
                .init(
                    error: error,
                    usage: toolCallUsage
                )
            )
        }

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

    private func beforeInvocation() async throws {
        print(#function)
    }

    private func beforeModelCall() async throws {
        print(#function)
    }

    private func afterModelCall() async throws {
        print(#function)
    }

    private func afterInvocation() async throws {
        print(#function)
    }

    private func beforeToolCall() async throws {
        print(#function)
    }

    private func afterToolCall() async throws {
        print(#function)
    }

    private func handleOnResponse(_ response: Transcript.Response) async throws
    {
        /// `history` will contains the last `Transcript.Response`

    }

    private func handleOnPrompt(_ prompt: Transcript.Prompt) async throws {
        /// remove the dummy empty prompt added when calling `responseStream`/`respond` used to force the retry from the updated history
        /// This will work as long as the transcript ends with prompt / tool output entry,
        /// which is indeed the case here.
        history.removeDummyPrompt()

        /// Internal Retry. Return early. No Hook triggered.
        if isInternalRetry {
            return
        }

        /// history will contain the prompt as its last entry
        ///
        /// NOTE: **Not** modifying history directly at the start
        /// so that in the case where handler throws
        /// we still have a clean history (managed by the FoundationModels SDK. Untouched)
        var historyBeforePrompt: Transcript.HistoryView = history
        historyBeforePrompt.removeAll {
            $0.asPrompt != nil && $0.id == prompt.id
        }

        let handlers = hookRegistry.beforeInvocationHandlers
        var event = BeforeInvocationEventHandler.EventPayload(
            prompt: prompt,
            agent: createLocalAgent(with: historyBeforePrompt)
        )

        for handler in handlers {
            try await handler.callback(&event)
        }

        /// Model call cancelled with a cancelled content. last-wins.
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

            /// programmatically triggers the `onResponse` Event
            try await self.handleOnResponse(response)

            throw ResponseFinishedError(response)
        }

        /// No changes to the tool Call. Return early.
        guard prompt != event.prompt else {
            return
        }

        /// Prompt modified. Last-wins
        ///
        /// NOTE: modifying the history here directly will indeed effect what the model sees (respond to),
        /// which is different from modifying the tool call in onToolCall where the model will NOT see the updated tool call parameters.
        self.history = historyBeforePrompt + [.prompt(event.prompt)]

    }

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
            try await handler.callback(&event)
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
        let tool = try getTool(for: toolCall)

        /// **Programmatically** call the wrapper tool.
        let outputTranscript = try await callTool(for: toolCall, using: tool)

        /// programmatically triggers the `onToolOutput` Event
        try await self.handleOnToolOutput(
            toolCall: toolCall,
            toolOutput: outputTranscript,
            attemptCount: attemptCount + 1
        )
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
            try await handler.callback(&event)
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
        let outputTranscript = try await callTool(for: toolCall, using: tool)

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
    private func callTool(
        for toolCall: Transcript.ToolCall,
        using tool: InvocableTool
    ) async throws
        -> Transcript.ToolOutput
    {
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

        return outputTranscript
    }

    private func createLocalAgent(with history: Transcript.HistoryView)
        -> LocalAgent
    {
        return LocalAgent(
            agentState: .init(\.agentState),
            invocationState: .init(\.invocationState),
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

    var toolCallError: ToolCallError? {
        return self.error(ToolCallError.self)
    }

    var responseFinishError: ResponseFinishedError? {
        return self.error(ResponseFinishedError.self)
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
