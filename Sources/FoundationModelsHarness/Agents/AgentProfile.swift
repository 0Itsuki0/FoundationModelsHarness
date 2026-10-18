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

//    @SessionProperty(\.invocationState)
//    private var invocationState
//
//    @SessionProperty(\.agentState)
//    private var agentState

//    @SessionProperty(\.hookRegistry)
//    private var hookRegistry

    @SessionProperty(\.history)
    private var history

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
        .onToolCall { toolCall in
            let lastToolCallsEvent =
                history.last?.asToolCalls ?? .init([toolCall])
            throw ToolCallsReceived(toolCalls: lastToolCallsEvent)
        }
    }
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

struct ToolCallsReceived: FakeError {
    var toolCalls: Transcript.ToolCalls
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
