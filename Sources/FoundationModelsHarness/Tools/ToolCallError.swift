//
//  ToolCallError.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

import FoundationModels

public struct ToolCallError: Error, Sendable {
    public let toolCall: Transcript.ToolCall
    public let error: Error
}

extension ToolCallError: CustomStringConvertible {
    public var description: String {
        return "(\(toolCall.toolName)) \(error.localizedDescription)"
    }
}
