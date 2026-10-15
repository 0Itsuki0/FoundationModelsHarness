//
//  AgentStreamEvent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// - `delegatedToolOutput` - Delegated tool output
/// - `contentUpdate` - streaming event from the model
public struct AgentStreamEvent: Sendable {
    public let event: Event

    public var usage: LanguageModelSession.Usage

    public var rawContent: GeneratedContent? {
        switch event {
        case .contentUpdate(let content):
            return content
        case .refusal(_):
            return nil
        case .toolUse(let toolCall):
            return toolCall.arguments
        case .toolOutput(let toolOutput):
            return toolOutput.segments.rawGeneratedContent
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
        self.event = .contentUpdate(rawContent)
        self.usage = usage
    }

    init(toolCall: Transcript.ToolCall, usage: LanguageModelSession.Usage) {
        self.event = .toolUse(toolCall)
        self.usage = usage
    }
    
    
    init(toolOutput: Transcript.ToolOutput, usage: LanguageModelSession.Usage) {
        self.event = .toolOutput(toolOutput)
        self.usage = usage
    }

    init(error: Error, usage: LanguageModelSession.Usage) {
        self.event = .refusal(error)
        self.usage = usage
    }
}

extension AgentStreamEvent {
    public enum Event: Sendable {
        case contentUpdate(GeneratedContent)

        case refusal(Error)

        case toolUse(Transcript.ToolCall)
        
        case toolOutput(Transcript.ToolOutput)
    }
}

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
