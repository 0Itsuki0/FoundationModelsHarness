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
    var invocationState

    @SessionProperty(\.agentState)
    var agentState

    @SessionProperty(\.hookRegistry)
    var hookRegistry

    @SessionProperty(\.history)
    var history

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
            //            print(prompt)
            print(history)
            //            history = history.prefix(history.count - 1)
            //            history.append(.prompt(.init(segments: [.text(.init(content: "greet dan"))])))
        }
        .onToolOutput { toolCall, toolOutput in
            print("onToolOutput")
            // history will contains the tool call but not the tool output
            print(history)

            let handlers = hookRegistry.afterToolCallHandlers
            var event = AfterToolCallEventHandler.EventPayload(
                toolCall: toolCall,
                toolOutput: toolOutput,
                agent: createLocalAgent()
            )
            for handler in handlers {
                try await handler.callback(&event)
            }
        }
        .onToolCall { toolCall in
            print("onToolCall")
            // history will contains the tool call
            print(history)

            let handlers = hookRegistry.beforeToolCallHandlers
            var event = BeforeToolCallEventHandler.EventPayload(
                toolCall: toolCall,
                agent: createLocalAgent()
            )
            for handler in handlers {
                try await handler.callback(&event)
            }
        }
    }

    private func createLocalAgent() -> LocalAgent {
        return LocalAgent(
            agentState: _agentState,
            invocationState: _invocationState,
            history: history
        )
    }
}
