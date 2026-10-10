//
//  AgentResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// - `delegatedToolOutput` - Delegated tool output
/// - `endTurn` - Natural end of the model's turn
public enum AgentResult: Sendable {
    case delegatedToolOutput(Transcript.ToolOutput)
    /// - rawContent: The raw response content.
    /// To convert it to a specific generable type, use `AgentResult.structuredOutput`
    /// - usage: Information about how many tokens were used by this response.
    case modelOutput(
        rawContent: GeneratedContent,
        usage: LanguageModelSession.Usage
    )

    public func structuredOutput<Value>(_ type: Value.Type = Value.self)
        -> Value?
    where Value: ConvertibleFromGeneratedContent {
        guard case .modelOutput(let rawContent, _) = self else {
            return nil
        }
        return try? rawContent.value()
    }

    public var text: String {
        switch self {
        case .modelOutput(let rawContent, _):
            rawContent.jsonString
        case .delegatedToolOutput(let output):
            output.segments.text
        }
    }
}
