//
//  AfterTools.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModels

/// Event triggered after all tools complete execution.
/// Fired after tool results are collected and ready to be added to conversation.
/// Uses reverse callback ordering for proper cleanup semantics.
///
/// Hook callbacks can:
/// - Set `endTurn` to short-circuit, for example, the tool outputs, directly to the output of the invocation without calling the model again to generate a response based on tool outputs.
///
/// *To modify output of individual tool call, use `AfterToolCall` hook instead.*
public struct AfterToolsEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .afterTools

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool output for each input tool call
        public let toolResults: [ToolCallResult]

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, including non-error tool outputs.
        public let agent: AgentSnapshot

        /// Set to a non-nil value to end the turn (agent loop) without calling the model again, aka: short-circuit to the output. (`JSONValue.null` will end the turn.)
        /// - The value set here will become the final assistant message content directly.
        /// - If `endTurn` is set to a non-nil value and any of the `ToolCallResult`'s `output` is failure, those will be wrapped with the `ToolOutputWrapper`(`status = error`) and added to the `history`.
        ///
        /// Read/write. Last-wins.
        ///
        /// `AfterInvocation` hook will be triggered.
        ///
        /// `stopReason` on the returned `AgentResult` is `endTurn`.
        public var endTurn: JSONValue?
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

extension AfterToolsEventHandler {
    enum CallbackHandlingResult: Sendable {
        case endTurn(Transcript.Response)
        case `continue`([ToolCallResult])
    }
}
