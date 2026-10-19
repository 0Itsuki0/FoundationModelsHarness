//
//  AgentProfile.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/11.
//

import FoundationModels

struct AgentProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history)
    private var history

    @SessionProperty(\.tools)
    private var tools

    @SessionProperty(\.model)
    private var model

    @SessionProperty(\.instruction)
    private var instruction

    var body: some LanguageModelSession.DynamicProfile {
        let instruction = ToolDelegationPlugin.injectDelegationPrompt(
            for: tools,
            on: instruction
        )

        Profile {
            instruction
            /// **IMPORTANT**:
            ///
            /// Attached the actual tool (not the wrapper) to the session  because if we have attached `invocableTool` to the session,
            /// any read on the`SessionProperties` within the actual `tool` will return their default value, as they are not attached to any sessions.
            tools.map(\.tool)
        }
        .model(model)
        /// `transcriptErrorHandlingPolicy` needs to be set to `preserveTranscript`.
        /// Otherwise, when we throw a FakeError, the previous request from the user will also be lost.
        .transcriptErrorHandlingPolicy(.preserveTranscript)
        .onPrompt {
            /// remove the dummy (empty) prompt added only for triggering model invocation
            /// Modifying history here works because
            /// 1. Foundation language models executing normally as long as the last transcript is tool output or user's prompt
            /// 2. modifying history directly here does effect what the model sees.
            history.removeDummyPrompt()
        }
        .onToolCall { toolCall in
            let lastToolCallsEvent =
                history.last?.asToolCalls ?? .init([toolCall])
            throw ToolCallsReceived(toolCalls: lastToolCallsEvent)
        }
    }
}

extension Transcript.HistoryView {
    mutating func removeDummyPrompt() {
        self = self.filter { !$0.isDummyPrompt }
    }
}

struct ToolCallsReceived: Error, Sendable {
    var toolCalls: Transcript.ToolCalls
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
