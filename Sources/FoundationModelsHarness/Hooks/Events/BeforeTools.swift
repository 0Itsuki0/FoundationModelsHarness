//
//  BeforeTools.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModels

/// Event triggered before executing tools.
/// Fired when the model returns tool use blocks that need to be executed.
///
/// Hook callbacks can:
/// - Set `cancel` to prevent all tools from executing.
///
/// *If modifying tool used / arguments passing into the tool is needed, use `BeforeToolCall` hook.*
public struct BeforeToolsEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeTools

    public let id = HookID()

    public struct EventPayload {
        /// The tool calls that triggers the event.
        public let toolCalls: [Transcript.ToolCall]

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, including the last tool calls
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel all tool calls with the value being the result error message. (`JSONValue.null` will cancel the tool call.)
        ///
        /// Read/write. Last-wins.
        ///
        /// `AfterTools` hook will be triggered, but **not** the `AfterToolCall` for individual `ToolOutput`.
        ///
        /// Setting `cancel` does NOT prevent the remaining handlers from being called.
        public var cancel: JSONValue? = nil
    }

    public let callback:nonisolated(nonsending) (inout EventPayload) async -> Void
    public let options: HookCallbackOptions?

    public init(
        callback: nonisolated(nonsending) @escaping (inout EventPayload) async -> Void,
        options: HookCallbackOptions? = nil
    ) {
        self.callback = callback
        self.options = options
    }
}


extension BeforeToolsEventHandler {
    enum CallbackHandlingResult: Sendable {
        case cancelled([(Transcript.ToolCall, Transcript.ToolOutput)])
        case `continue`
    }
}
