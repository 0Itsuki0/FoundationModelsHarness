//
//  ModelStopData.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/15.
//

//
//  AgentResult.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct ModelStopData: Sendable {

    public let stopReason: ModelStopReason

    public let invocationState: InvocationState

    public let usage: LanguageModelSession.Usage

    public var rawContent: GeneratedContent? {
        switch stopReason {
        case .endTurn(let response):
            return response.segments.rawGeneratedContent
        case .refusal(_):
            return nil
        case .toolUse(let toolCalls):
            return GeneratedContent(kind: .array(toolCalls.map(\.arguments)))
        }
    }

    init(
        stopReason: ModelStopReason,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = stopReason
        self.invocationState = invocationState
        self.usage = usage
    }

    init(
        response: Transcript.Response,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .endTurn(response)
        self.invocationState = invocationState
        self.usage = usage
    }

    init(
        toolCalls: Transcript.ToolCalls,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .toolUse(toolCalls)
        self.invocationState = invocationState
        self.usage = usage
    }

    init(
        error: Error,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .refusal(error)
        self.invocationState = invocationState
        self.usage = usage
    }

}

extension ModelStopData: CustomStringConvertible {
    public var description: String {
        return stopReason.description
    }
}

public enum ModelStopReason: Sendable {
    case endTurn(Transcript.Response)

    case refusal(Error)

    case toolUse(Transcript.ToolCalls)

    // TODO: - map foundation model error to specific stop reason
    //    init(error: Error) {
    //        if let
    //    }
}

extension ModelStopReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .endTurn(let response):
            return response.description
        case .refusal(let error):
            return error.localizedDescription
        case .toolUse(let toolCall):
            return toolCall.description
        }
    }
}
