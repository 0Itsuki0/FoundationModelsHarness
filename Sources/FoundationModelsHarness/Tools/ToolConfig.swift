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
    /// `InvocableTool` wrapping the `tool` for programatic invocation
    let invocableTool: InvocableTool

    /// Actual `Tool` being wrapped and **attached to the session**.
    ///
    /// **IMPORTANT**:
    /// This is the one that is attached to the session  because if we have attached `invocableTool` to the session,
    /// any read on the`SessionProperties` within the actual `tool` will return their default value, as they are not attached to any sessions.
    let tool: any Tool

    /// When a tool is configured with `delegate: true`, this package ensures:
    /// 1. The agent loop exits immediately after a successful delegation (via endTurn)
    /// 2. The delegation tool's content blocks become the final assistant message
    /// and
    /// on best effort: The delegation tool is the only tool called in the turn
    ///
    /// NOTE:
    /// If a  delegated tool output a result,
    /// the `AfterModelCall` hook will not be triggered (as there is no model called for the final response).
    let delegate: Bool

    /// - `tool`: the tool being added to the session
    /// - `delegate`: whether to configured the tool as a delegated tool.
    ///     When a tool is configured with `delegate: true`, this package ensures:
    ///     1. The agent loop exits immediately after a successful delegation (via endTurn)
    ///     2. The delegation tool's content blocks become the final assistant message
    public init<T: Tool>(tool: T, delegate: Bool = false) {
        self.invocableTool = InvocableTool(
            tool: tool
        )
        self.delegate = delegate
        self.tool = tool
    }
}

extension ToolConfig {
    static let DELEGATION_DESCRIPTION_SUFFIX = """
        Calling any delegated tool will return its response directly to the user as the final answer.
        It should be the **only** tool called in the turn.
        """

    static func injectDelegationPrompt(
        for tools: [ToolConfig],
        on instruction: Instructions
    ) -> Instructions {
        let delegatedTools = tools.filter({ $0.delegate })
        let toolNames = delegatedTools.map(\.tool.name)
        guard !toolNames.isEmpty else {
            return instruction
        }
        return Instructions {
            instruction
            """
            Delegated Tools: \(toolNames.joined(separator: ", "))
            \(DELEGATION_DESCRIPTION_SUFFIX)
            """
        }
    }
}
