//
//  AgentResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct AgentResult: Sendable {

    public private(set) var stopReason: AgentStopReason

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
        if let error = error as? HookCallbackError {
            self = .init(
                errors: [error],
                invocationState: invocationState,
                usage: usage
            )
            return
        }
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

    init(
        errors: [HookCallbackError],
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .hookCallbackError(errors)
        self.invocationState = invocationState
        self.usage = usage
    }

    mutating func setError(_ error: HookCallbackError) {
        if case .hookCallbackError(var errors) = self.stopReason {
            errors.append(error)
            self.stopReason = .hookCallbackError(errors)
        } else {
            self.stopReason = .hookCallbackError([error])
        }
    }
}

/// - `delegatedToolOutput` - Delegated tool output.
///    In the case of a `delegatedToolOutput`, `AfterInvocation` hook will not be triggered (as there is no model called for the final response).
/// - `endTurn` - Natural end of the model's turn
public enum AgentStopReason: Sendable {
    case endTurn(Transcript.Response)

    case refusal(Error)

    case toolCallError([ToolCallError])

    case hookCallbackError([HookCallbackError])
}

public struct ToolCallError: Error, Sendable {
    var toolCall: Transcript.ToolCall
    var error: Error
}

public struct HookCallbackError: Error, Sendable {
    var event: HookEventType
    var error: Error
}
