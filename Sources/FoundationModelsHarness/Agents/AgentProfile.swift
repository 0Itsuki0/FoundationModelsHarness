//
//  AgentProfile.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/11.
//

import FoundationModels

struct AgentProfile: LanguageModelSession.DynamicProfile {
    let tools: [ToolConfig]
    let instruction: Instructions

    @SessionProperty(\.invocationState)
    private var invocationState

    @SessionProperty(\.agentState)
    private var agentState

    @SessionProperty(\.hookRegistry)
    private var hookRegistry

    @SessionProperty(\.history)
    private var history

    @SessionProperty(\.isInternalRetry)
    private var isInternalRetry

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            instruction
            /// **IMPORTANT**:
            ///
            /// Attached the actual tool (not the wrapper) to the session  because if we have attached `invocableTool` to the session,
            /// any read on the`SessionProperties` within the actual `tool` will return their default value, as they are not attached to any sessions.
            tools.map(\.tool)
        }
        /// `transcriptErrorHandlingPolicy` needs to be set to `preserveTranscript`.
        /// Otherwise, when we throw a FakeError, the previous request from the user will also be lost.
        .transcriptErrorHandlingPolicy(.preserveTranscript)
        .onPrompt {
            history.removeDummyPrompt()
        }
//        .onToolOutput { toolCall, toolOutput in
//            try await handleOnToolOutput(
//                toolCall: toolCall,
//                toolOutput: toolOutput
//            )
//        }
//        .onToolCall(perform: handleOnToolCall)
        .onToolCall {
            throw ToolCallError(toolCall: $0)
        }
//        .onResponse(perform: handleOnResponse)
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

//    private func handleOnToolOutput(
//        toolCall: Transcript.ToolCall,
//        toolOutput: Transcript.ToolOutput,
//        attemptCount: Int = 1
//    ) async throws {
//        /// `history` will contains the last Transcript.ToolCalls entry but should **NOT** contain the `Transcript.ToolOutput`
//        /// However, still do a defensive filtering here.
//        var historyBeforeOutput = history
//        historyBeforeOutput.removeAll {
//            $0.asToolOutput != nil && $0.id == toolOutput.id
//        }
//
//        let handlers = hookRegistry.afterToolCallHandlers
//        var event = AfterToolCallEventHandler.EventPayload(
//            toolCall: toolCall,
//            toolOutput: toolOutput,
//            agent: createLocalAgent(with: historyBeforeOutput),
//            attemptCount: max(1, attemptCount)
//        )
//
//        for handler in handlers {
//            try await handler.callback(&event)
//        }
//
//        // TODO: - handle event.toolOutput change
//
//        /// Retry Tool call. last-wins.
//        if event.retry {
//            return try await retryToolCall(toolCall, attemptCount: attemptCount)
//        }
//
//        /// Short-circuit to the output with the `endTurn` value
//        if let endTurn = event.endTurn {
//            /// programmatically append tool output to history
//            self.history.append(.toolOutput(event.toolOutput))
//
//            /// programmatically append `endTurn` as model response to history
//            let response = Transcript.Response(
//                segments: SegmentBuilder.segments(
//                    from: endTurn,
//                    schemaName: "GeneratedContent"
//                )
//            )
//            self.history.append(.response(response))
//
//            /// programmatically trigger `onResponse`
//            try await self.handleOnResponse(response)
//
//            /// throw `ResponseFinishedError` to break out of the agent loop
//            throw ResponseFinishedError(response)
//        }
//    }
//
//    private func retryToolCall(
//        _ toolCall: Transcript.ToolCall,
//        attemptCount: Int
//    ) async throws {
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
//    }
//
//    /// Handle Tool calls on the Profile.
//    private func handleOnToolCall(_ toolCall: Transcript.ToolCall) async throws
//    {
//        /// `history` will contains the last Transcript.ToolCalls entry
//        /// (which contains the toolCall: Transcript.ToolCall as one of the calls)
//        ///
//        /// NOTE: **Not** modifying history directly at the start
//        /// so that in the case where handler throws
//        /// we still have a clean history (managed by the FoundationModels SDK. Untouched)
//        let historyBeforeLastToolCall: Transcript.HistoryView
//        /// extracted last tool calls event
//        let lastToolCallsEvent: Transcript.ToolCalls
//
//        if let lastHistory = history.last?.asToolCalls {
//            historyBeforeLastToolCall = history.prefix(history.count - 1)
//            lastToolCallsEvent = lastHistory
//        } else {
//            historyBeforeLastToolCall = history
//            lastToolCallsEvent = .init([toolCall])
//        }
//
//        let calls = lastToolCallsEvent.expand()
//
//        let handlers = hookRegistry.beforeToolCallHandlers
//        var event = BeforeToolCallEventHandler.EventPayload(
//            toolCall: toolCall,
//            toolCalls: calls,
//            agent: createLocalAgent(with: historyBeforeLastToolCall)
//        )
//
//        for handler in handlers {
//            try await handler.callback(&event)
//        }
//
//        /// Tool call cancelled with a cancelled content. last-wins.
//        if let cancel = event.cancel {
//            return try await handleToolCallCancelled(cancel, on: toolCall)
//        }
//
//        /// No changes to the tool Call. Return early.
//        guard toolCall != event.toolCall else {
//            return
//        }
//
//        /// Handle tool input / name changes. last-wins.
//        try await self.handleToolCallUpdated(
//            toolCalls: lastToolCallsEvent,
//            previousId: toolCall.id,
//            updated: event.toolCall,
//            historyBeforeLastToolCall: historyBeforeLastToolCall
//        )
//    }
//
//    /// Tool call cancelled
//    private func handleToolCallCancelled(
//        _ cancellationContent: JSONValue,
//        on toolCall: Transcript.ToolCall
//    )
//        async throws
//    {
//        let toolOutput = ToolOutputWrapper(cancellationContent, status: .error)
//        let outputTranscript = Transcript.ToolOutput(
//            id: toolCall.id,
//            toolName: toolCall.toolName,
//            segments: toolOutput.segments
//        )
//
//        /// programmatically triggers the `onToolOutput` Event
//        try await self.handleOnToolOutput(
//            toolCall: toolCall,
//            toolOutput: outputTranscript
//        )
//
//        /// Add in the tool output to the session's history
//        ///
//        /// NOTE: do this *after* the `handleOnToolOutput` because for the `onToolOutput` triggered by the system,
//        /// the `history` will contains the last Transcript.ToolCalls entry but **NOT** the `Transcript.ToolOutput`
//        self.history.append(
//            .toolOutput(outputTranscript)
//        )
//
//        /// throw retry error to force the model to generate a response based on the tool output.
//        throw RetryModelGenerationError.afterToolOutput
//    }
//
//    /// Tool call parameters (name, input argument, and etc) updated.
//    ///
//    /// Since updating the `history` in `onToolCall` will **only** reflected to the session history,
//    /// aka:  effect what the model sees **On the next turn**.
//    /// but not **NOT** effect the actual argument used to call the tool nor which tool is called.
//    /// Therefore, we will be
//    /// 1. manually calling the tool
//    /// 2. append the tool output to the history
//    /// 3. throw to terminate the current turn
//    /// 4. retry the generation with the tool already outputted
//    private func handleToolCallUpdated(
//        toolCalls: Transcript.ToolCalls,
//        previousId: Transcript.ToolCall.ID,
//        updated toolCall: Transcript.ToolCall,
//        historyBeforeLastToolCall: Transcript.HistoryView
//    )
//        async throws
//    {
//        /// since the `invocableTool` is a wrapper around the `tool` passing in, both share the same arguments, output, schema, name
//        let tool = try getTool(for: toolCall)
//
//        var calls = toolCalls.expand()
//
//        /// update the target tool call
//        if let index = calls.firstIndex(where: { $0.id == previousId }) {
//            calls[index] = toolCall
//        } else {
//            calls.append(toolCall)
//        }
//        /// Add back the Transcript.ToolCalls and assign it to the history.
//        //
//        /// modifying the history here will effect what the model sees **On the next turn**.
//        /// It will **NOT** effect the actual argument used to call the tool nor which tool is called.
//        //
//        /// NOTE: that we need to set `self.history` twice: once here, once after the `handleOnToolOutput`,
//        /// because if one of the AfterToolCallEventHandler throws an error,
//        /// we still want to record the updated tool call.
//        self.history =
//            historyBeforeLastToolCall + [
//                .toolCalls(.init(id: toolCalls.id, calls))
//            ]
//
//        /// **Programmatically** call the wrapper tool if there is a change.
//        ///
//        /// This is needed because even if we have modified the session history with the new toolCall Parameter,
//        /// (aka: history = historyTemp)
//        /// the model will still use the previous tool name / arguments.
//        let outputTranscript = try await callTool(for: toolCall, using: tool)
//
//        /// programmatically triggers the `onToolOutput` Event
//        try await self.handleOnToolOutput(
//            toolCall: toolCall,
//            toolOutput: outputTranscript
//        )
//
//        /// Add in the tool output to the session's history
//        ///
//        /// NOTE: do this *after* the `handleOnToolOutput` because for the `onToolOutput` triggered by the system,
//        /// the `history` will contains the last Transcript.ToolCalls entry but **NOT** the `Transcript.ToolOutput`
//        self.history.append(
//            .toolOutput(outputTranscript)
//        )
//
//        /// throw retry error to force the model to generate a response based on the tool output.
//        throw RetryModelGenerationError.afterToolOutput
//    }
//
//    private func getTool(for toolCall: Transcript.ToolCall) throws
//        -> InvocableTool
//    {
//        guard
//            let tool = self.tools.first(where: {
//                $0.invocableTool.name == toolCall.toolName
//            })?.invocableTool
//        else {
//            throw LanguageModelError.refusal(
//                .init(
//                    explanation: "Tool \(toolCall.toolName) is not registered.",
//                    debugDescription:
//                        "Register \(toolCall.toolName) and try again."
//                )
//            )
//        }
//        return tool
//    }
//
//    /// **Programmatically** call the wrapper tool
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
//
//    private func createLocalAgent(with history: Transcript.HistoryView)
//        -> AgentSnapshot
//    {
//        return AgentSnapshot(
//            agentState: _agentState,
//            invocationState: _invocationState,
//            history: history
//        )
//    }
//
//    func toolOutputSegments(
//        from output: InvocableTool.Output,
//        schemaName: String
//    ) async -> [Transcript.Segment] {
//        let output = output.output
//        let segments = await SegmentBuilder.segments(
//            from: output.promptRepresentation
//        )
//        if segments.isEmpty {
//            if let generatedContent = output as? ConvertibleToGeneratedContent {
//                return SegmentBuilder.segments(
//                    from: GeneratedContent(generatedContent),
//                    schemaName: schemaName
//                )
//            }
//            return [Transcript.Segment.text(.init(content: "\(output)"))]
//        }
//
//        return segments
//    }
}

enum RetryModelGenerationError: FakeError, Equatable, Hashable {
    /// retry model generation based on tool output
    case afterToolOutput
}

extension Transcript.HistoryView {
    mutating func removeDummyPrompt() {
        self = self.filter { !$0.isDummyPrompt }
    }

    //    mutating func removeEmptyEntry() {
    //        self = self.filter {
    //            $0.asResponse?.segments.isEmpty != true
    //                || $0.asPrompt?.segments.isEmpty != true
    //        }
    //    }
}

extension Transcript.Segment {
    var isAttachment: Bool {
        if case .attachment(_) = self {
            return true
        }
        return false
    }
}

extension Transcript.ToolCalls {
    func expand() -> [Transcript.ToolCall] {
        return Array(self)
    }
}

struct ToolCallError: FakeError {
    var toolCall: Transcript.ToolCall
}

// this is probably never needed if we are always executing the tool ourselves.
//struct ToolOutputError: FakeError {
//    var toolCall: Transcript.ToolCall
//    var toolOutput: Transcript.ToolOutput
//}

enum InternalMetadataKey {
    static let dummyPrompt = "FoundationModelHarness_dummyPrompt"
}

extension Transcript.Entry {
    var isDummyPrompt: Bool {
        switch self {
        case .prompt(let value):
            value.metadata[InternalMetadataKey.dummyPrompt] != nil
        default:
            false
        }
    }
}

struct ResponseFinishedError: FakeError {
    let response: Transcript.Response

    init(_ response: Transcript.Response) {
        self.response = response
    }
}
