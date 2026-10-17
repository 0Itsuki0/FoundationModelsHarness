//
//  BeforeInvocation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Event triggered at the beginning of a new agent request.
/// Fired before any model inference or tool execution occurs.
///
/// Hook callbacks can:
/// - Set `cancel` to cancel this invocation.
public struct BeforeInvocationEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeInvocation

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The prompt to be sent to the model.
        ///
        /// Read/write. Last-wins.
        ///
        /// - Mutate `prompt` in place to modify what will be sent to the model for generating a response.
        public var prompt: Transcript.Prompt

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, up to **(not including)** the current prompt
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel this model call. (`JSONValue.null` will cancel the call.)
        /// The value set here will be used as the model  response.
        ///
        /// Read/write. Last-wins.
        ///
        /// `AfterInvocation` hook will be triggered with the model response created from the `cancel` value.
        ///
        /// **NOTE**:
        /// Setting `cancel` do NOT prevent the remaining `BeforeInvocationEventHandler` from being called.
        /// - Later callbacks see the cancel. They get the same event object, so they can read event.cancel and skip their own work with
        /// something like if (event.cancel) return.
        /// - Later callbacks can undo the cancel
        /// - Later callback can change the cancel value (message used as the model response)
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

extension BeforeInvocationEventHandler {
    enum CallbackHandlingResult: Sendable {
        case cancelled(Transcript.Response)
        case `continue`(Transcript.Prompt)
    }
}
