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

    @SessionProperty(\.isRetry)
    private var isRetry

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            instruction
            tools.map(\.tool)
        }
        // `transcriptErrorHandlingPolicy` needs to be set to `preserveTranscript`.
        // Otherwise, when we throw a FakeError, the previous request from the user will also be lost.
        .transcriptErrorHandlingPolicy(.preserveTranscript)
        .onPrompt { prompt in
            // history will contain the prompt as its last entry
            // modifying the history here directly will effect what the model sees.
            // Use it for context injection & BeforeModelCall event for prompt transformation
            // TODO: add context injection / BeforeModelCall hook
            print("on prompt")
            print(history)
            // remove the dummy empty prompt sent to force the retry from the history
            // as long as the transcript ends with prompt / tool output, the respond or response stream works
            if isRetry {
                history = history.prefix(history.count - 1)
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

    private func handleOnToolCall(_ toolCall: Transcript.ToolCall) async throws
    {
        print(#function)
        // history will contains the last Transcript.ToolCalls entry
        // (which contains the toolCall: Transcript.ToolCall as one of the calls)
        // create a temporary history removing it
        //
        // NOTE: Not modifying history directly at the start
        // so that in the case where handler throws
        // we still have a clean history (managed by the FoundationModels SDK. Untouched)
        var historyTemp = history
        // extracted last tool calls event
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

        // No changes to the tool Call. Return early.
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

    private func handleToolCallUpdate(
        toolCalls: Transcript.ToolCalls,
        previousId: Transcript.ToolCall.ID,
        updated toolCall: Transcript.ToolCall,
        historyTemp: Transcript.HistoryView
    )
        async throws
    {
        guard
            let tool = self.tools.first(where: {
                $0.tool.name == toolCall.toolName
            })?.tool
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

        // update the target tool call
        if let index = calls.firstIndex(where: { $0.id == previousId }) {
            calls[index] = toolCall
        } else {
            calls.append(toolCall)
        }
        // Add back the Transcript.ToolCalls and assign it to the history.
        //
        // modifying the history here will effect what the model sees **On the next turn**.
        // It will **NOT** effect the actual argument used to call the tool nor which tool is called.
        //
        // NOTE: that we need to set `self.history` twice: once here, once after the `handleOnToolOutput`,
        // because if one of the AfterToolCallEventHandler throws an error,
        // we still want to record the updated tool call.
        historyTemp.append(
            .toolCalls(.init(id: toolCalls.id, calls))
        )

        self.history = historyTemp

        // Programmatically call the tool if there is a change.
        // This is needed because
        // even if we have modified the session history with the new toolCall Parameter,
        // (aka: history = historyTemp)
        // the model will still use the previous tool name / arguments.
        let toolOutput = try await tool.call(
            arguments: toolCall.arguments
        )

        let outputTranscript = Transcript.ToolOutput(
            id: toolCall.id,
            toolName: toolCall.toolName,
            segments: [
                .structure(
                    .init(
                        schemaName: tool.parameters.name,
                        content: toolOutput
                    )
                )
            ]
        )

        // programmatically triggers the onToolOutput Event
        try await self.handleOnToolOutput(
            toolCall,
            toolOutput: outputTranscript
        )

        // Add in the tool output to the session's history
        historyTemp.append(
            .toolOutput(outputTranscript)
        )

        self.history = historyTemp

        // throw retry error to force the modal to generate a response based on the tool output.
        throw RetryError()
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
}

struct RetryError: FakeError {}

extension Transcript.ToolCalls {
    func expand() -> [Transcript.ToolCall] {
        return Array(self)
    }
}
