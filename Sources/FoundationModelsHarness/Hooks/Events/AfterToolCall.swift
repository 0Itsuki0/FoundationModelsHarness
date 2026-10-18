//
//  AfterToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Event triggered after a tool execution completes.
/// Fired after tool execution finishes, whether successful or failed.
/// Uses reverse callback ordering for proper cleanup semantics.
///
/// Hook callbacks can mutate `toolResult` to rewrite the tool result before it propagates to the model (e.g. to redact or truncate output).
public struct AfterToolCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .afterToolCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool call that triggers the output.
        public let toolCall: Transcript.ToolCall

        /// The output of the tool call.
        ///
        /// Read/write. Last-wins.
        ///
        /// Can be mutated / replaced by hook callbacks to transform the result before it enters the conversation history.
        /// Failure is the error thrown by the `Tool.call(arguments:)`.
        /// Any error here will be penetrated directly up to agent result as `toolCallError`.
        ///
        /// Changes in the `Transcript.ToolOutput`'s `id` and `toolName` will be ignored as those will need to be paired up with the `toolCall`
        public var toolResult: Result<Transcript.ToolOutput, Error>

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

extension AfterToolCallEventHandler {
    enum CallbackHandlingResult: Sendable {
        case retry
        case `continue`(Result<Transcript.ToolOutput, Error>)
    }
}
