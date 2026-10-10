//
//  AgentStreamEvent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// - `delegatedToolOutput` - Delegated tool output
/// - `contentUpdate` - streaming event from the model
public enum AgentStreamEvent: Sendable {
    case contentUpdate(
        rawContent: GeneratedContent,
        usage: LanguageModelSession.Usage
    )
    case delegatedToolOutput(Transcript.ToolOutput)
    
    public func structuredContent<Value>(_ type: Value.Type = Value.self)
    -> Value?
    where Value: ConvertibleFromGeneratedContent {
        guard case .contentUpdate(let rawContent, _) = self else {
            return nil
        }
        return try? rawContent.value()
    }
    
    public var text: String {
        switch self {
        case .contentUpdate(let rawContent, _):
            rawContent.jsonString
        case .delegatedToolOutput(let output):
            output.segments.text
        }
    }
}
