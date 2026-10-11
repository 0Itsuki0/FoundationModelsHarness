//
//  ToolConfig.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Tool Configuration
public struct ToolConfig: Sendable {
    let tool: InvocableTool
    /// NOTE:
    /// If a  delegated tool output a result,
    /// the `AfterModelCall` hook will not be triggered (as there is no model called for the final response).
    let delegate: Bool

    public init(tool: InvocableTool, delegate: Bool) {
        self.tool = tool
        self.delegate = delegate
    }

    public init<T: Tool>(tool: T, delegate: Bool, type: T.Type = T.self)
    where T.Output: Generable {
        self.tool = InvocableTool(tool: tool)
        self.delegate = delegate
    }

    public init<T: Tool>(tool: T, delegate: Bool, type: T.Type = T.self)
    where T.Output: ConvertibleToGeneratedContent {
        self.tool = InvocableTool(tool: tool)
        self.delegate = delegate
    }
}
