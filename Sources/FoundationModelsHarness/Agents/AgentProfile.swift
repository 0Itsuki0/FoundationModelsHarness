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
        .onPrompt { prompt in

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
            historyBeforePrompt.removeAll { $0.id == prompt.id }

            let handlers = hookRegistry.beforeModelCallHandlers
            var event = BeforeModelCallEventHandler.EventPayload(
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
        .onToolOutput(perform: handleOnToolOutput)
        .onToolCall(perform: handleOnToolCall)
        .onResponse(perform: handleOnResponse)
    }

    private func handleOnResponse(_ response: Transcript.Response) async throws
    {
        /// `history` will contains the last `Transcript.Response`

    }

    // TODO: - 
    private func handleOnToolOutput(
        toolCall: Transcript.ToolCall,
        toolOutput: Transcript.ToolOutput
    ) async throws {
        /// `history` will contains the last Transcript.ToolCalls entry but **NOT** the `Transcript.ToolOutput`
        let handlers = hookRegistry.afterToolCallHandlers
        var event = AfterToolCallEventHandler.EventPayload(
            toolCall: toolCall,
            toolOutput: toolOutput,
            agent: createLocalAgent(with: history)
        )
        for handler in handlers {
            try await handler.callback(&event)
        }
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

    private func createLocalAgent(with history: Transcript.HistoryView)
        -> LocalAgent
    {
        return LocalAgent(
            agentState: _agentState,
            invocationState: _invocationState,
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

enum RetryModelGenerationError: FakeError, Equatable, Hashable {
    /// retry model generation based on tool output
    case afterToolOutput
}

extension Transcript.HistoryView {
    mutating func removeDummyPrompt() {
        self = self.filter({ !$0.isDummyPrompt })
    }
}

extension Transcript.ToolCalls {
    func expand() -> [Transcript.ToolCall] {
        return Array(self)
    }
}

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
