//
//  AfterToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct AfterToolCallEventHandler: HookEventHandler {
    public struct EventPayload: Sendable {
        let toolCall: Transcript.ToolCall
        let toolOutput: Transcript.ToolOutput
        let agent: LocalAgent
    }

    static public let eventType: HookEventType = .afterToolCall

    public let callback: @Sendable (EventPayload) async throws -> Void
    public let options: HookCallbackOptions?

    init(
        callback: @escaping @Sendable (EventPayload) async throws -> Void,
        options: HookCallbackOptions?
    ) {
        self.callback = callback
        self.options = options
    }
}
