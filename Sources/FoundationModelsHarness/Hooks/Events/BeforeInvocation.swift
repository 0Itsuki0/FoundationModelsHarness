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
/// - Mutate `prompt` in place to modify what is sent to the model. You can use it, for example, for Context Injection.
public struct BeforeInvocationEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeInvocation

    public let id = HookID()

    public struct EventPayload {
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
        /// - `configuration`: Current Agent Configurations including tools, hooks, plugins, and instruction used.
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel this model call. (`JSONValue.null` will cancel the call.)
        /// The value set here will be used as the model  response.
        ///
        /// Read/write. Last-wins.
        ///
        /// `stopReason` on the returned `AgentResult` is `endTurn`.
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

extension BeforeInvocationEventHandler {
    enum CallbackHandlingResult: Sendable {
        case cancelled(Transcript.Response)
        case `continue`(Transcript.Prompt)
    }
}
