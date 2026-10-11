//
//  BeforeToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct BeforeToolCallEventHandler: HookEventHandler {
    public let id = HookID()

    public struct EventPayload: Sendable {
        let toolCall: Transcript.ToolCall
        let agent: LocalAgent

        // TODO: add hook cancellation. (cancel with a message that will be send back to the model)
        // strands-ts/src/agent/agent.ts: line 2450
    }

    static public let eventType: HookEventType = .beforeToolCall

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

extension Array where Element == BeforeToolCallEventHandler {
    var sortedByHookOrder: [Element] {
        self.sortedByHookOrder(
            order: \.order,
            useReverseOrder: BeforeToolCallEventHandler.useReverseOrder
        )
    }
}
