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
        case .refusal(let error):
            return nil
        case .toolUse(let toolCall):
            return toolCall.arguments
        }
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
        toolCall: Transcript.ToolCall,
        invocationState: InvocationState,
        usage: LanguageModelSession.Usage
    ) {
        self.stopReason = .toolUse(toolCall)
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

public enum ModelStopReason: Sendable {
    case endTurn(Transcript.Response)

    case refusal(Error)

    case toolUse(Transcript.ToolCall)

    // TODO: - map foundation model error to specific stop reason
    //    init(error: Error) {
    //        if let
    //    }
}
