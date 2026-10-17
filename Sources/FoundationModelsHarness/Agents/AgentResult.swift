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
        default:
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

extension AgentResult: CustomStringConvertible {
    public var description: String {
        self.stopReason.description
    }
}

extension AgentStopReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .endTurn(let response):
            return response.description
        case .refusal(let error):
            return "(Model refusal) \(error.localizedDescription)"
        case .toolCallError(let toolCallError):
            return "(Tool call error) " + toolCallError.map(\.description).joined(separator: ".")
        }
    }
}

public struct ToolCallError: Error, Sendable {
    public let toolCall: Transcript.ToolCall
    public let error: Error
}

extension ToolCallError: CustomStringConvertible {
    public var description: String {
        return "(\(toolCall.toolName)) \(error.localizedDescription)"
    }
}
