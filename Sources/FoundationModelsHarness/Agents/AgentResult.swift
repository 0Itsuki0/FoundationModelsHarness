//
//  AgentResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct AgentResult: Sendable {

    public let stopReason: AgentStopReason

    public let invocationState: InvocationState

    public let usage: LanguageModelSession.Usage

    public var rawContent: GeneratedContent? {
        switch stopReason {
        case .endTurn(let response):
            return response.segments.rawGeneratedContent
        case .refusal(_):
            return nil
        case .toolCallError(_):
            return nil
        }
    }

    init(
        response: Transcript.Response,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .endTurn(response)
        self.invocationState = invocationState
        self.usage = usage
    }

    init(
        error: Error,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .refusal(error)
        self.invocationState = invocationState
        self.usage = usage
    }

    init(
        error: [ToolCallError],
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .toolCallError(error)
        self.invocationState = invocationState
        self.usage = usage
    }
}

/// - `delegatedToolOutput` - Delegated tool output.
///    In the case of a `delegatedToolOutput`, `AfterInvocation` hook will not be triggered (as there is no model called for the final response).
/// - `endTurn` - Natural end of the model's turn
public enum AgentStopReason: Sendable {
    case endTurn(Transcript.Response)

    case refusal(Error)

    case toolCallError([ToolCallError])
}

public struct ToolCallError: Error, Sendable {
    var toolCall: Transcript.ToolCall
    var error: Error
}
