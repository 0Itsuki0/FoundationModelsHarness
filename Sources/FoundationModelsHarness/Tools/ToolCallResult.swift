//
//  ToolCallResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

import FoundationModels

public struct ToolCallResult: Sendable {
    public let toolCall: Transcript.ToolCall

    /// The error here, if present, will be penetrate to the `AgentResult` directly as `AgentStopReason.ToolCallError`
    public let result: Result<Transcript.ToolOutput, Error>
}
