//
//  AgentResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// - `delegatedToolOutput` - Delegated tool output
/// - `endTurn` - Natural end of the model's turn
public struct AgentResult: Sendable {
    public let stopReason: StopReason

    public let lastMessage: Transcript.Response

    public let invocationState: InvocationState

    /// This is **NOT** the usage obtained directly from a `LanguageModelSession.Response`,
    /// but the full turn usage that can include tool use, reasoning, and etc.
    public let usage: LanguageModelSession.Usage

    public var rawContent: GeneratedContent? {
        lastMessage.segments.rawGeneratedContent
    }
}

/// - `delegatedToolOutput` - Delegated tool output.
///    In the case of a `delegatedToolOutput`, `AfterInvocation` hook will not be triggered (as there is no model called for the final response).
/// - `endTurn` - Natural end of the model's turn
public enum StopReason: Sendable {
    //    case delegatedToolOutput
    //    case modelOutput
    case endTurn
}
