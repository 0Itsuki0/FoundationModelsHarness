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
            /// history will contain the prompt as its last entry
            /// modifying the history here directly will effect what the model sees (respond to),
            /// which is different from modifying the tool call in onToolCall where the model will NOT see the updated tool call parameters.

            /// Use it for context injection & BeforeModelCall event for prompt transformation
            /// TODO: add context injection / BeforeModelCall hook
            print("on prompt")
            print(history)
            /// remove the dummy empty prompt added when calling `responseStream`/`respond` used to force the retry from the updated history
            /// This will work as long as the transcript ends with prompt / tool output entry,
            /// which is indeed the case here.
            history.removeDummyPrompt()
            /// Internal Retry. Return early. No Hook triggered.
            if isInternalRetry {
                return
            }
        }
        .onToolOutput(perform: handleOnToolOutput)
        .onToolCall(perform: handleOnToolCall)
    }

    private func handleOnToolOutput(
        _ toolCall: Transcript.ToolCall,
        toolOutput: Transcript.ToolOutput
    ) async throws {
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
        print(#function)
        /// history will contains the last Transcript.ToolCalls entry
        /// (which contains the toolCall: Transcript.ToolCall as one of the calls)
        /// create a temporary history removing it
        ///
        /// NOTE: Not modifying history directly at the start
        /// so that in the case where handler throws
        /// we still have a clean history (managed by the FoundationModels SDK. Untouched)
        var historyTemp = history
        /// extracted last tool calls event
        let lastToolCallsEvent =
            historyTemp.popLast()?.asToolCalls ?? .init([toolCall])
        let calls = lastToolCallsEvent.expand()

        let handlers = hookRegistry.beforeToolCallHandlers
        var event = BeforeToolCallEventHandler.EventPayload(
            toolCall: toolCall,
            toolCalls: calls,
            agent: createLocalAgent(with: historyTemp)
        )

        for handler in handlers {
            try await handler.callback(&event)
        }

        /// No changes to the tool Call. Return early.
        guard toolCall != event.toolCall else {
            return
        }

        try await self.handleToolCallUpdate(
            toolCalls: lastToolCallsEvent,
            previousId: toolCall.id,
            updated: event.toolCall,
            historyTemp: historyTemp
        )
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
    private func handleToolCallUpdate(
        toolCalls: Transcript.ToolCalls,
        previousId: Transcript.ToolCall.ID,
        updated toolCall: Transcript.ToolCall,
        historyTemp: Transcript.HistoryView
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
        var historyTemp = historyTemp

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
        historyTemp.append(
            .toolCalls(.init(id: toolCalls.id, calls))
        )

        self.history = historyTemp

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

        /// programmatically triggers the onToolOutput Event
        try await self.handleOnToolOutput(
            toolCall,
            toolOutput: outputTranscript
        )

        /// Add in the tool output to the session's history
        historyTemp.append(
            .toolOutput(outputTranscript)
        )

        self.history = historyTemp

        /// throw retry error to force the modal to generate a response based on the tool output.
        throw RetryError.afterToolOutput
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

    /// Create segments mirroring how system handles it.
    private func segments(
        from generatedContent: GeneratedContent,
        schemaName: String
    ) -> [Transcript.Segment] {
        switch generatedContent.kind {
        case .null:
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]
        case .bool(let value):
            return [.text(.init(content: String(value)))]
        case .number(let value):
            return [.text(.init(content: String(value)))]
        case .string(let value):
            return [.text(.init(content: value))]
        case .array(let value):
            return value.flatMap {
                segments(from: $0, schemaName: schemaName)
            }
        case .structure(_, _):
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]
        @unknown default:
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]

        }
    }

    func segments(from instructions: InstructionsRepresentable)
        -> [Transcript.Segment]
    {
        let session = LanguageModelSession(
            instructions: instructions.instructionsRepresentation
        )
        return session.transcript.compactMap { $0.asInstruction }.first?
            .segments ?? []
    }

    func toolOutputSegments(
        from output: InvocableTool.Output,
        schemaName: String
    ) async -> [Transcript.Segment] {
        let output = output.output
        let segments = await self.segments(from: output.promptRepresentation)
        if segments.isEmpty {
            if let generatedContent = output as? ConvertibleToGeneratedContent {
                return self.segments(
                    from: GeneratedContent(generatedContent),
                    schemaName: schemaName
                )
            }
            return [Transcript.Segment.text(.init(content: "\(output)"))]
        }

        return segments
    }

    /// PromptRepresentable:
    /// Inheritance: ConvertibleToGeneratedContent, Generable
    /// conformance type: ImageReference, Attachment, GeneratedContent, Prompt
    func segments(from prompt: PromptRepresentable) async -> [Transcript
        .Segment]
    {
        /// ConvertibleToGeneratedContent, Generable, ImageReference, Attachment, GeneratedContent
        /// all conforms to InstructionsRepresentable and will be handled here.
        if let instructions = prompt as? InstructionsRepresentable {
            return segments(from: instructions)
        }

        let profile = LanguageModelSession.Profile {}.onPrompt {
            throw PromptReceived(prompt: $0)
        }

        let session = LanguageModelSession(profile: profile)
        /// make sure the prompt is preserved even when there is an error calling the model
        session.transcriptErrorHandlingPolicy = .preserveTranscript
        let prompt = prompt.promptRepresentation
        do {
            let _ = try await session.respond(to: prompt)
        } catch {
            if let error = error as? PromptReceived {
                return error.prompt.segments
            }
        }
        /// fallback if the PromptReceived is never caught
        return session.transcript.history.compactMap { $0.asPrompt }.first?
            .segments ?? []
    }

}

enum RetryError: FakeError, Equatable, Hashable {
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

private struct PromptReceived: Error {
    let prompt: Transcript.Prompt
}
