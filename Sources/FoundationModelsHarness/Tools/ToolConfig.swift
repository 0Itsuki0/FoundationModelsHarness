//
//  ToolConfig.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

// TODO: - maybe consider create a full wrapper for the tool to expose LocalAgent to Tool.call

public struct ToolConfig: Sendable {
    let tool: any Tool
    let delegate: Bool

    public init(tool: any Tool, delegate: Bool) {
        self.tool = tool
        self.delegate = delegate
    }
}
