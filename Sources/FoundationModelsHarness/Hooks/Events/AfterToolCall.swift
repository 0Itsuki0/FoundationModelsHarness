//
//  AfterToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct AfterToolCallEventHandler: HookEventHandler {
    public let id = HookID()

    public struct EventPayload: Sendable {
        let toolCall: Transcript.ToolCall
        let toolOutput: Transcript.ToolOutput
        /// History in agent will not contain the tool output
        let agent: LocalAgent

        // TODO: add hook endTurn. (end the turn with a message that will be used directly as model's output)
        // strands-ts/src/agent/agent.ts: line 1784
    }

    static public let eventType: HookEventType = .afterToolCall

    public let callback: @Sendable (inout EventPayload) async throws -> Void
    public let options: HookCallbackOptions?

    public init(
        callback: @escaping @Sendable (inout EventPayload) async throws -> Void,
        options: HookCallbackOptions? = nil
    ) {
        self.callback = callback
        self.options = options
    }
}

extension Array where Element == AfterToolCallEventHandler {
    var sortedByHookOrder: [Element] {
        self.sortedByHookOrder(
            order: \.order,
            useReverseOrder: AfterToolCallEventHandler.useReverseOrder
        )
    }
}
