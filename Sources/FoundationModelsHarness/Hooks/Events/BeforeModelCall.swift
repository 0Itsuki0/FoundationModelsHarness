//
//  BeforeModelCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/15.
//

import FoundationModels

/// Event triggered just before the model is invoked.
/// This hook will be triggered in two scenarios.
/// 1. sending the user's prompt for a response
/// 2. sending tool outputs for generating a final response
///
/// Hook callbacks can:
/// - Set `cancel` to prevent the model from executing.
///     - Behavior wise, setting `cancel` here after a tool call is almost the same as setting `endTurn` in `AfterTools`, and setting it after a user prompt is almost the same as setting `cancel` in `BeforeInvocation`. Therefore, the use of `BeforeModelCallEventHandler.cancel` is when the decision is about the model call itself, such as a budget, turn limit, or a policy gate on any model call.
///
/// *If modifying user's prompt is needed, use `BeforeInvocation` hook. *
/// *If modifying tool result is needed, use `AfterToolCall` hook*
public struct BeforeModelCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeModelCall

    public let id = HookID()

    public struct EventPayload: Sendable {

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present,  including the current prompt or tool output that triggers the event.
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel this model call. (`JSONValue.null` will cancel the call.)
        /// The value set here will be used as the model  response.
        ///
        /// Read/write. Last-wins.
        ///
        /// `stopReason` on the returned `AgentResult` is `'endTurn'`.
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


extension BeforeModelCallEventHandler {
    enum CallbackHandlingResult: Sendable {
        case cancelled(Transcript.Response)
        case `continue`
    }
}
