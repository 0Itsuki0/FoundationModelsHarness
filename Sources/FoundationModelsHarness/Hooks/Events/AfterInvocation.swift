//
//  AfterInvocation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/14.
//

import FoundationModels

/// Event triggered at the end of an agent request.
/// Fired after all processing completes, regardless of success or error.
/// Uses reverse callback ordering for proper cleanup semantics.
///
/// Hook callbacks can:
/// -  use this event for cleanup, logging, or state persistence
/// - Set `resume` to trigger a follow-up agent invocation with new input. When set, after this event's callbacks complete the agent re-enters its loop with these args as new input, under the same invocation lock.
/// - Set `retry` to rollback and retry the entire  invocation.
public struct AfterInvocationEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .afterInvocation

    public let id = HookID()

    public struct EventPayload {
        /// The result of the agent invocation.
        public let result: AgentResult

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, including the last response, if not errored.
        /// - `tools`: currently registered tools
        public let agent: AgentSnapshot

        /// Boolean flag that can be set by hook callbacks to request a retry of the full invocation.
        /// When set to true, the history will rollback to before the invocation, and retry the entire invocation.
        ///
        /// Read/write. Last-wins.
        ///
        /// If both`retry` and `resume` is set, `resume`will be ignored.
        public var retry: Bool = false

        /// 1-indexed count of model attempts for this turn, including the attempt
        /// that just completed (or failed). The first call in a turn is `1`; each
        /// subsequent retry increments by one.
        /// Retry strategies may rely on `attemptCount === 1` to mark the start of a
        /// new retry sequence (e.g. to clear per-turn state carried over from a
        /// previous turn). The agent loop guarantees this marker on every fresh turn.
        public let attemptCount: Int

        /// Set to a non-nil value to re-invoke the agent.
        /// The value set here will be used as the model  input.
        ///
        /// Read/write. Last-wins.
        ///
        /// If both`retry` and `resume` is set, `resume`will be ignored.
        public var resume: Prompt? = nil

    }

    public let callback:
        nonisolated(nonsending) (inout EventPayload) async -> Void
    public let options: HookCallbackOptions?

    public init(
        callback:
            nonisolated(nonsending) @escaping (inout EventPayload) async -> Void,
        options: HookCallbackOptions? = nil
    ) {
        self.callback = callback
        self.options = options
    }
}

extension AfterInvocationEventHandler {
    enum CallbackHandlingResult: Sendable {
        case resume(Prompt)
        case retry
        case finish
    }
}
