//
//  ToolDelegationPlugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

import FoundationModels

/// `ToolDelegationPlugin`:
/// short-circuit tool output directly to agent output (if success) instead of sending the tool output back to the model to generate a final response.
///
/// using an `actor` here to handle potential parallel hook callbacks.
/// Non-public to avoid re-using one instance for multiple agent.
actor ToolDelegationPlugin: Plugin {
    static let name: PluginName =
        "\(reservedPackagePrefix)_ToolDelegationPlugin"

    private var delegatedTools: [ToolName]

    /// current delegated tool that is being executed.
    private var executingToolCallId: Transcript.ToolCall.ID?

    private var hooks: [any HookEventHandler] {
        return [
            BeforeModelCallEventHandler(
                callback: { _ in await self.reset() },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            ),
            BeforeToolCallEventHandler(
                callback: { await self.beforeToolCall(&$0) },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            ),
            AfterToolsEventHandler(
                callback: { await self.afterTools(&$0) },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            ),
        ]
    }

    init(_ delegatedTools: [String] = []) {
        self.delegatedTools = delegatedTools
    }

    /// NOTE: not modifying the instruction here as it will need to be dynamic based on tool configuration
    func initAgent(_ agent: Agent) {
        let _ = hooks.map(agent.addHook(_:))
    }

    func deInitAgent(_ agent: Agent) {}

    private func getExecutingToolCallId() -> String? {
        return self.executingToolCallId
    }

    private func eraseExecutingToolCallId() {
        self.executingToolCallId = nil
        return
    }

    private func getDelegatedTools() -> [ToolName] {
        return self.delegatedTools
    }

    nonisolated func setDelegatedTools(_ delegatedTools: [String]) async {
        await self._setDelegatedTools(delegatedTools)
    }

    private func _setDelegatedTools(_ delegatedTools: [String]) {
        self.delegatedTools = delegatedTools
    }

    /// returning whether if the set is successful or not
    /// Get and set in one transaction to make sure that it is reflected correctly even when multiple hook callback is fired in parallel.
    private func trySetExecutingToolCallId(_ name: String) -> Bool {
        guard self.executingToolCallId == nil else {
            return false
        }
        self.executingToolCallId = name
        return true
    }

    /// reset the `executingToolCallId` per model call (NOT per invoke) so that the state can be fresh on retries or continuous model invocations.
    private func reset() async {
        self.eraseExecutingToolCallId()
    }

    /// cancel all other tool calls that are not delegated tools if there is a delegated tool being / will be executed this turn
    private func beforeToolCall(
        _ event: inout BeforeToolCallEventHandler.EventPayload
    ) async {
        let delegatedTools = getDelegatedTools()
        /// no delegated tool calls in this turn at all. return early.
        guard
            event.toolCalls.map(\.toolName).contains(where: {
                delegatedTools.contains($0)
            })
        else { return }

        /// current tool being executed is the delegated tool && no delegated tool is being executed yet.
        /// If the tool mode is parallel, those might still coming in before
        if delegatedTools.contains(event.toolCall.toolName),
            self.trySetExecutingToolCallId(event.toolCall.id)
        {
            return
        }

        /// already executing some other deleted tool or
        /// a delegated tool is pending to be executed.
        /// cancel the current tool call
        cancelToolCall(&event)
        return

    }

    private func cancelToolCall(
        _ event: inout BeforeToolCallEventHandler.EventPayload
    ) {
        event.cancel = .string(
            """
            This tool call [\(event.toolCall)] is cancelled because another delegated tool is being called and a delegated tool has to be the **only** tool called in the turn.
            Try again.
            """
        )
    }

    nonisolated private func afterTools(
        _ event: inout AfterToolsEventHandler.EventPayload
    ) async {
        let executingId = await self.getExecutingToolCallId()
        guard
            let first = event.toolResults.first(where: {
                $0.toolCall.id == executingId
            })
        else {
            return
        }

        switch first.result {
        case .success(let success):
            event.endTurn =
                (try? JSONValue(success.segments.rawGeneratedContent))
                ?? .string(success.segments.description)
        case .failure(_):
            /// errors will be penetrated directly to the agent result as toolCallError
            return
        }
    }
}

extension ToolDelegationPlugin {
    static let DELEGATION_DESCRIPTION_SUFFIX = """
        Calling any delegated tool will return its response directly to the user as the final answer.
        It should be the **only** tool called in the turn.
        """

    static func injectDelegationPrompt(
        for tools: [ToolConfig],
        on instruction: Instructions
    ) -> Instructions {
        let delegatedTools = tools.filter({ $0.delegate })
        let toolNames = delegatedTools.map(\.tool.name)
        guard !toolNames.isEmpty else {
            return instruction
        }
        return Instructions {
            instruction
            """
            Delegated Tools: \(toolNames.joined(separator: ", "))
            \(DELEGATION_DESCRIPTION_SUFFIX)
            """
        }
    }

    static func delegationInstruction(
        for tools: [ToolName],
    ) -> Instructions {
        guard !tools.isEmpty else {
            return Instructions {}
        }
        return Instructions {
            """
            Delegated Tools: \(tools.joined(separator: ", "))
            \(DELEGATION_DESCRIPTION_SUFFIX)
            """
        }
    }
}
