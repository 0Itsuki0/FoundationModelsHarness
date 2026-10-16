//
//  AfterToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

public struct AfterToolCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .afterToolCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool call that triggers the output.
        ///
        /// Read only.
        public let toolCall: Transcript.ToolCall

        // TODO: - change this to a result where the failure is the error thrown by the tool
        // error will be penetrated directly up to agent result after the *After* hooks being called.
        /// The output of the tool call.
        ///
        /// Read/write. Last-wins.
        ///
        /// Can be mutated / replaced by hook callbacks to transform the result before it enters the conversation history.
        public var toolOutput: Transcript.ToolOutput

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, up to **(not including)** the last tool output
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

        /// Set to a non-nil value to end the turn (agent loop) after this tool completes. (`JSONValue.null` will end the turn.)
        /// The value set here will become the final assistant message content directly.
        ///
        /// Read/write. Last-wins.
        ///
        /// `AfterInvocation` hook will be triggered with the model response created from the `endTurn` value.
        ///
        /// `stopReason` on the returned `AgentResult` is `'endTurn'`.
        public var endTurn: JSONValue?

    }

    /// the error thrown will be propagated up directly to the `respond` or `streamResponse` after the *After* hooks being called.
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
