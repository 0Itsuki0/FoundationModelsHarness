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
    public var rawContent: GeneratedContent
    public var usage: LanguageModelSession.Usage

    public func structuredContent<Value>(_ type: Value.Type = Value.self)
        -> Value?
    where Value: ConvertibleFromGeneratedContent {
        return try? rawContent.value()
    }

    public var text: String {
        rawContent.jsonString
    }

    init(rawContent: GeneratedContent, usage: LanguageModelSession.Usage) {
        self.rawContent = rawContent
        self.usage = usage
    }

    init(segments: [Transcript.Segment], usage: LanguageModelSession.Usage) {
        self.init(
            rawContent: segments.rawGeneratedContent,
            usage: usage
        )
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

    var isStrictEmpty: Bool {
        if self.isEmpty {
            return true
        }
        if self.contains(where: { $0.isAttachment }) {
            return false
        }

        return self.rawContent.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }
}
