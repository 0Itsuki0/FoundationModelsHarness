//
//  AfterModelCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModels

/// Event triggered after the model invocation completes
/// Fired after the model finishes generating a response, whether successful or failed.
/// Uses reverse callback ordering for proper cleanup semantics.
public struct AfterModelCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .afterModelCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The output of the model.
        ///
        /// Read/write.
        ///
        /// Can be mutated / replaced by hook callbacks to transform the result before it enters the conversation history and eventually change the next step. For example, changing tool use to an endTurn will end the turn with the message set directly.
        public var stopReason: ModelStopReason

        /// usage in this model call.
        public let usage: LanguageModelSession.Usage

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, including the last response if not errored.
        public let agent: AgentSnapshot

        /// Boolean flag that can be set by hook callbacks to request a retry of the tool call.
        /// When set to true, the agent will re-execute the tool.
        ///
        /// Read/write. Last-wins.
        public var retry: Bool = false

        /// 1-indexed count of model attempts for this turn, including the attempt
        /// that just completed (or failed). The first call in a turn is `1`; each
        /// subsequent retry increments by one.
        /// Retry strategies may rely on `attemptCount === 1` to mark the start of a
        /// new retry sequence (e.g. to clear per-turn state carried over from a
        /// previous turn). The agent loop guarantees this marker on every fresh turn.
        public let attemptCount: Int

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

extension AfterModelCallEventHandler {
    enum CallbackHandlingResult: Sendable {
        case retry
        case `continue`(ModelStopReason)
    }
}
