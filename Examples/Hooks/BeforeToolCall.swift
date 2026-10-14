//
//  BeforeToolCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/14.
//

import FoundationModelsHarness

/// Before tool call hook: triggered just before a tool is executed.
///
/// Example:
/// - `stateAccessing`: Read/write states that ca also be read/write from the tools / other hook handlers
/// - `cancellation`: Cancel the tool call with a message
/// - `toolCallMutation`: change the tool name / parameters
enum BeforeToolCallExample {
    case stateAccessing
    case cancellation
    case toolCallMutation
}

private func testStream(_ agent: Agent) async throws {
    try await printStream(agent.streamResponse(to: "greet itsuki"))
    printHistory(agent.transcript.history)
}

private func testRespond(_ agent: Agent) async throws {
    let _ = try await agent.respond(to: "greet itsuki")
    printHistory(agent.transcript.history)
}

private func setupCancellation(_ agent: Agent) {
    agent.addHook(
        BeforeToolCallEventHandler(
            callback: { event in
                // cancel the tool call
                event.cancel = .init(
                    stringLiteral: "failed to greet. Do it yourself."
                )
            },
            // set a custom order.
            // cancellation mutation is last win so we might want to run it as late as possible
            options: .init(order: BuiltInHookOrder.sdkLast.rawValue + 1)
        )
    )

}

private func setupToolCallMutation(_ agent: Agent) {
    agent.addHook(
        BeforeToolCallEventHandler(callback: { event in
            // modify tool calls
            event.toolCall.toolName = GreetingTool().name
            let argument = GreetingTool.Arguments(name: "⭐⭐itsuki⭐⭐")
            event.toolCall.arguments = argument.generatedContent
        })
    )
}

private func setUpStateAccessing(_ agent: Agent) {
    agent.addHook(
        BeforeToolCallEventHandler(callback: { event in
            print(
                """
                BeforeToolCallEventHandler triggered: 
                invocationState: \(event.agent.invocationState)
                agentState: \(event.agent.agentState)
                history: \(event.agent.history)
                """
            )

            // set state
            let toolCount =
                event.agent.agentState["tool_count"]?.asInt() ?? 0 + 1
            event.agent.agentState["tool_count"] = .number(
                Double(toolCount)
            )
        })
    )
}

func beforeToolCallHook(stream: Bool = false, example: BeforeToolCallExample)
    async throws
{
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: false)],
        instruction: .init("You are a helpful assistant.")
    )

    switch example {

    case .stateAccessing:
        setUpStateAccessing(agent)
    case .cancellation:
        setupCancellation(agent)
    case .toolCallMutation:
        setupToolCallMutation(agent)
    }

    stream ? try await testStream(agent) : try await testRespond(agent)
}
