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
/// - Mutate `toolCall` in place, or replace it wholesale, to rewrite the tool input or name before execution. The `name` has to be one of the registered tools. If it  is changed, a different tool will be called.
public struct BeforeToolCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeToolCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool call that triggers the event.
        ///
        /// Read/write. Last-wins (If a later `BeforeToolCallEventHandler` modifies the `toolCall` , that one will be the one executed.).
        ///
        /// Mutate `toolCall` in place, or replace it wholesale, to rewrite the tool input or name before execution. The `name` has to be one of the registered tools. If it  is changed, a different tool will be called. If a tool with the given name cannot be found, a `Transcript.ToolOutput` indicating that the tool is missing will be create and added to the history for the model to generate a final response
        public var toolCall: Transcript.ToolCall

        /// All tools being called in the current turn including the one triggers the event.
        /// This is the same as the last entry of `agent.history`.
        public let toolCalls: [Transcript.ToolCall]

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, including the last tool calls
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel this tool call with the value being the result error message. (`JSONValue.null` will cancel the tool call.)
        ///
        /// Read/write. Last-wins.
        ///
        /// `AfterToolCall` hook will be triggered with the `Transcript.ToolOutput` created.
        ///
        /// Setting `cancel` does NOT prevent the remaining handlers from being called.
        public var cancel: JSONValue? = nil
    }

    public let callback: @Sendable (inout EventPayload) async -> Void
    public let options: HookCallbackOptions?

    public init(
        callback: @escaping @Sendable (inout EventPayload) async -> Void,
        options: HookCallbackOptions? = nil
    ) {
        self.callback = callback
        self.options = options
    }
}

extension BeforeToolCallEventHandler {
    enum CallbackHandlingResult: Sendable {
        case cancelled(Transcript.ToolOutput)
        case `continue`(Transcript.ToolCall)
    }
}
