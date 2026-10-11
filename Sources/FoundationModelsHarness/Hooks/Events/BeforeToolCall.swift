//
//  BeforeToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Event triggered just before a tool is executed.
/// Fired after tool lookup but before execution begins.
///
/// Hook callbacks can:
/// - Set `cancel` to prevent the tool from executing.
/// - Mutate `toolCall` in place, or replace it wholesale, to rewrite the tool
///   input or name before execution.
///   The `name` has to be one of the registered tools. If it  is changed, a different tool will be called.
public struct BeforeToolCallEventHandler: HookEventHandler {
    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool call that triggers the event
        public var toolCall: Transcript.ToolCall
        
        /// All tools being called right now including the one triggers the event
        public let toolCalls: [Transcript.ToolCall]

        /// LocalAgent.History contains transcript history up to (not including) the last tool calls
        public let agent: LocalAgent

        // TODO: add hook cancellation. (cancel with a message that will be send back to the model)
        // strands-ts/src/agent/agent.ts: line 2450
    }

    static public let eventType: HookEventType = .beforeToolCall

    /// the error thrown will be propagated up directly to the `respond` or `streamResponse`.
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
