//
//  ToolConfig.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Tool Configuration:
/// - `tool`: the tool being added to the session
/// - `delegate`: whether to configured the tool as a delegated tool.
///     When a tool is configured with `delegate: true`, this package ensures:
///     1. The agent loop exits immediately after a successful delegation (via endTurn)
///     2. The delegation tool's content blocks become the final assistant message
public struct ToolConfig: Sendable {
    var toolName: String {
        self.tool.name
    }

    /// `InvocableTool` wrapping the `tool` for programatic invocation
    let invocableTool: InvocableTool

    /// Actual `Tool` being wrapped and **attached to the session**.
    ///
    /// **IMPORTANT**:
    /// This is the one that is attached to the session  because if we have attached `invocableTool` to the session,
    /// any read on the`SessionProperties` within the actual `tool` will return their default value, as they are not attached to any sessions.
    public let tool: any Tool

    /// When a tool is configured with `delegate: true`, this package ensures:
    /// 1. The agent loop exits immediately after a successful delegation (via endTurn)
    /// 2. The delegation tool's content blocks become the final assistant message
    /// 3. The delegation tool is the only tool called in the turn
    public let delegate: Bool

    /// - `tool`: the tool being added to the session
    /// - `delegate`: whether to configured the tool as a delegated tool.
    ///     When a tool is configured with `delegate: true`, this package ensures:
    ///     1. The agent loop exits immediately after a successful delegation (via endTurn)
    ///     2. The delegation tool's content blocks become the final assistant message
    ///     3. The delegation tool is the only tool called in the turn
    public init<T: Tool>(tool: T, delegate: Bool = false) {
        self.invocableTool = InvocableTool(
            tool: tool
        )
        self.delegate = delegate
        self.tool = tool
    }
}
