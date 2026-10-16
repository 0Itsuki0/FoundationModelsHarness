//
//  BeforeToolCallEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Event triggered just before a tool is executed.
/// Fired after tool lookup but before execution begins.
///
/// Hook callbacks can:
/// - Set `cancel` to prevent the tool from executing.
/// - Mutate `toolCall` in place, or replace it wholesale, to rewrite the tool
///   input or name before execution.
///   The `name` has to be one of the registered tools. If it  is changed, a different tool will be called.
public struct BeforeToolCallEventHandler: HookEventHandler {
    static public let eventType: HookEventType = .beforeToolCall

    public let id = HookID()

    public struct EventPayload: Sendable {
        /// The tool call that triggers the event.
        ///
        /// Read/write. Last-wins (If a later `BeforeToolCallEventHandler` modifies the `toolCall` , that one will be the one executed.).
        ///
        /// - Mutate `toolCall` in place, or replace it wholesale, to rewrite the tool
        ///   input or name before execution.
        ///   The `name` has to be one of the registered tools. If it  is changed, a different tool will be called.'
        public var toolCall: Transcript.ToolCall

        /// All tools being called in the current turn including the one triggers the event
        ///
        /// Read only.
        public let toolCalls: [Transcript.ToolCall]

        /// Following parameters accessible through`agent`:
        ///
        /// - `agentState`: Agent state persists across requests. Read/write.
        /// - `invocationState`: Invocation state lives for a single invocation. Read/write.
        /// - `history`: The transcript entries excluding the leading instructions entry, if present, up to **(not including)** the last tool calls
        public let agent: AgentSnapshot

        /// Set to a non-nil value to cancel this tool call with the value being the result error message. (`JSONValue.null` will cancel the tool call.)
        ///
        /// Read/write. Last-wins.
        ///
        /// A `Transcript.ToolOutput` will be created from the value here and send back to the model for a final response.
        /// The `ToolOutput` segments will be one single `Transcript.StructuredSegment` created with the JSON representation of `ToolOutputWrapper`
        /// where the `content` is the value set on the `cancel`,  and the `status` being `Status.error`.
        ///
        /// `AfterToolCall` hook will be triggered with the `Transcript.ToolOutput` created.
        ///
        /// **NOTE**:
        /// Setting `cancel` do NOT prevent the remaining `BeforeToolCallEventHandler` from being called.
        /// - Later callbacks see the cancel. They get the same event object, so they can read event.cancel and skip their own work with
        /// something like if (event.cancel) return.
        /// - Later callbacks can undo the cancel
        /// - Later callback can change the cancel value (message used as the tool output)
        public var cancel: JSONValue? = nil
    }

        /// If an error is thrown here,
    /// - the rest of the handlers for *this* event will be skipped
    /// - the remaining *After* hooks will still be called
    /// - error will be propagated up **directly** to the `AgentResult`
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

/// A generic Tool output for a cancelled tool call
public struct ToolOutputWrapper: ConvertibleToGeneratedContent {
    static let schemaName = "ToolOutput"

    public var generatedContent: GeneratedContent {
        GeneratedContent(properties: [
            "status": status,
            "content": content.generatedContent,
        ])
    }

    @Generable
    enum Status {
        case success
        case error
    }

    let status: Status
    let content: JSONValue
    init(_ content: JSONValue, status: Status) {
        self.content = content
        self.status = .error
    }

    var segments: [Transcript.Segment] {
        return SegmentBuilder.segments(
            from: self.generatedContent,
            schemaName: Self.schemaName
        )
    }
}
