//
//  BeforeModelCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Event triggered just before a prompt is sent to the model.
///
/// **NOTE**
/// The event will NOT be triggered when sending tool results back to the model for a response.
///
/// Hook callbacks can:
/// - Set `cancel` to prevent the model from executing.
/// - Mutate `prompt` in place to modify what is sent to the model. You can use it, for example, for Context Injection.
public struct BeforeModelCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeModelCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The prompt that triggers the event.
        ///
        /// Read/write.
        ///
        /// - Mutate `prompt` in place to modify what will be sent to the model for generating a response.
        public var prompt: Transcript.Prompt

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, up to **(not including)** the current prompt
        public let agent: LocalAgent

        /// Set to a non-nil value to cancel this model call. (`JSONValue.null` will cancel the call.)
        /// The value set here will be used as the model  response.
        ///
        /// Read/write.
        ///
        /// `AfterModelCall` hook will be triggered with the `Transcript.Response` created above.
        ///
        /// **NOTE**:
        /// Setting `cancel` do NOT prevent the remaining `BeforeModelCallEventHandler` from being called.
        /// - Later callbacks see the cancel. They get the same event object, so they can read event.cancel and skip their own work with
        /// something like if (event.cancel) return.
        /// - Later callbacks can undo the cancel
        /// - Later callback can change the cancel value (message used as the model response)
        public var cancel: JSONValue? = nil
    }

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
