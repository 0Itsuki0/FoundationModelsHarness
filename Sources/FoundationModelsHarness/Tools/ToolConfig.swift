//
//  ToolConfig.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Tool Configuration
public struct ToolConfig: Sendable {
    /// `InvocableTool` wrapping the `tool` for programatic invocation
    let invocableTool: InvocableTool

    /// Actual `Tool` being wrapped and **attached to the session**.
    ///
    /// **IMPORTANT**:
    /// This is the one that is attached to the session  because if we have attached `invocableTool` to the session,
    /// any read on the`SessionProperties` within the actual `tool` will return their default value, as they are not attached to any sessions.
    let tool: any Tool

    /// NOTE:
    /// If a  delegated tool output a result,
    /// the `AfterModelCall` hook will not be triggered (as there is no model called for the final response).
    let delegate: Bool

    public init(tool: InvocableTool, delegate: Bool = false) {
        self.invocableTool = tool
        self.delegate = delegate
        self.tool = tool
    }

    public init<T: Tool>(tool: T, delegate: Bool = false) {
        self.invocableTool = InvocableTool(
            tool: tool
        )
        self.delegate = delegate
        self.tool = tool
    }
}
