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

    case contentUpdate(GeneratedContent, LanguageModelSession.Usage)

    case modelStop(ModelStopData)

    case refusal(Error, LanguageModelSession.Usage)

    case toolCall(Transcript.ToolCall)

    case toolResult(Result<Transcript.ToolOutput, Error>)

    case agentResult(AgentResult, LanguageModelSession.Usage)

    public var rawContent: GeneratedContent? {
        switch self {
        case .contentUpdate(let content, _):
            return content
        case .modelStop(let stopData):
            return stopData.rawContent
        case .refusal(_, _):
            return nil
        case .toolCall(let toolCall):
            return toolCall.arguments
        case .toolResult(let result):
            switch result {
            case .success(let success):
                return success.segments.rawGeneratedContent
            case .failure(let failure):
                return GeneratedContent(
                    kind: .string(failure.localizedDescription)
                )
            }
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

    init(modelStop: ModelStopData) {
        self = .modelStop(modelStop)
    }

    init(toolCall: Transcript.ToolCall) {
        self = .toolCall(toolCall)
    }

    init(toolResult: Result<Transcript.ToolOutput, Error>) {
        self = .toolResult(toolResult)
    }

    init(error: Error, usage: LanguageModelSession.Usage) {
        self = .refusal(error, usage)
    }

    init(result: AgentResult, usage: LanguageModelSession.Usage) {
        self = .agentResult(result, usage)
    }
}

extension AgentStreamEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .contentUpdate(let content, _):
            return "(Content update) \(content.jsonString)"
        case .modelStop(let stopData):
            return "(Model stop) \(stopData.description)"
        case .refusal(let error, _):
            return "(Refusal) \(error.localizedDescription)"
        case .toolCall(let toolCall):
            return "(Tool call) \(toolCall.description)"
        case .toolResult(let result):
            switch result {
            case .success(let success):
                return success.description
            case .failure(let failure):
                return "(Tool output error) \(failure.localizedDescription)"
            }
        case .agentResult(let result, _):
            return "(Agent result) \(result.description)"
        }
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
