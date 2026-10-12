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
    
//    public let rawContent: GeneratedContent
    // TODO: consider manually calculating usage
//    public let usage: LanguageModelSession.Usage
}

/// - `delegatedToolOutput` - Delegated tool output.
///    In the case of a `delegatedToolOutput`, `AfterModelCall` hook will not be triggered (as there is no model called for the final response).
/// - `endTurn` - Natural end of the model's turn
public enum StopReason: Sendable {
    case delegatedToolOutput
    case modelOutput
    case cancellation
}
