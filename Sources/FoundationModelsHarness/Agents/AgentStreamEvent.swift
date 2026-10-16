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
    //    public let event: Event
    //
    //    public var usage: LanguageModelSession.Usage
    case contentUpdate(GeneratedContent, LanguageModelSession.Usage)

    case refusal(Error, LanguageModelSession.Usage)

    case toolUse(Transcript.ToolCall)

    case toolOutput(Transcript.ToolOutput)

    case agentResult(AgentResult, LanguageModelSession.Usage)

    public var rawContent: GeneratedContent? {
        switch self {
        case .contentUpdate(let content, _):
            return content
        case .refusal(_, _):
            return nil
        case .toolUse(let toolCall):
            return toolCall.arguments
        case .toolOutput(let toolOutput):
            return toolOutput.segments.rawGeneratedContent
        case .agentResult(let result, _):
            return result.rawContent
        }
    }

    public func structuredContent<Value>(_ type: Value.Type = Value.self)
        -> Value?
    where Value: ConvertibleFromGeneratedContent {
        return try? rawContent?.value()
    }

    public var text: String? {
        rawContent?.jsonString
    }

    init(rawContent: GeneratedContent, usage: LanguageModelSession.Usage) {
        self = .contentUpdate(rawContent, usage)
    }

    init(toolCall: Transcript.ToolCall) {
        self = .toolUse(toolCall)
    }

    init(toolOutput: Transcript.ToolOutput) {
        self = .toolOutput(toolOutput)
    }

    init(error: Error, usage: LanguageModelSession.Usage) {
        self = .refusal(error, usage)
    }

    init(result: AgentResult, usage: LanguageModelSession.Usage) {
        self = .agentResult(result, usage)
    }
}

//enum AgentStreamEvent {
//    //    public enum Event: Sendable {
//    case contentUpdate(GeneratedContent, LanguageModelSession.Usage)
//
//    case refusal(Error, LanguageModelSession.Usage)
//
//    case toolUse(Transcript.ToolCall)
//
//    case toolOutput(Transcript.ToolOutput)
//
//    case agentResult(AgentResult, LanguageModelSession.Usage)
//    //    }
//}

extension Array where Element == Transcript.Segment {
    var rawContent: String {
        return self.compactMap { segment -> String? in
            switch segment {
            case .text(let text):
                text.content.isEmpty ? nil : text.content
            case .structure(let structure):
                structure.content.jsonString
            case .attachment(_):
                nil
            @unknown default:
                nil
            }
        }.joined(separator: "\n")
    }

    var rawGeneratedContent: GeneratedContent {
        return (try? GeneratedContent(json: self.rawContent))
            ?? GeneratedContent(kind: .string(self.rawContent))
    }

    //    var isStrictEmpty: Bool {
    //        if self.isEmpty {
    //            return true
    //        }
    //        if self.contains(where: { $0.isAttachment }) {
    //            return false
    //        }
    //
    //        return self.rawContent.trimmingCharacters(
    //            in: .whitespacesAndNewlines
    //        ).isEmpty
    //    }
}
