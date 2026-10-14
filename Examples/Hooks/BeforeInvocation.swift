//
//  BeforeInvocation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/14.
//

import FoundationModelsHarness

/// Before model call hook:  triggered just before a prompt is sent to the model..
///
/// Example:
/// - `stateAccessing`: Read/write states that ca also be read/write from the tools / other hook handlers
/// - `cancellation`: Cancel the model invocation with a message
/// - `promptMutation`: change the prompt
enum BeforeInvocationExample {
    case stateAccessing
    case cancellation
    case promptMutation
}

private func testStream(_ agent: Agent) async throws {
    try await printStream(agent.streamResponse(to: "Hello"))
    printHistory(agent.transcript.history)
}

private func testRespond(_ agent: Agent) async throws {
    let _ = try await agent.respond(to: "Hello")
    printHistory(agent.transcript.history)
}

private func setupCancellation(_ agent: Agent) {
    agent.addHook(
        BeforeInvocationEventHandler(
            callback: { event in
                // cancel the tool call
                event.cancel = .init(
                    stringLiteral: "Service temporarily not available"
                )
            },
            // set a custom order.
            // cancellation mutation is last win so we might want to run it as late as possible
            options: .init(order: BuiltInHookOrder.sdkLast.rawValue + 1)
        )
    )
}

private func setupPromptMutation(_ agent: Agent) {
    agent.addHook(
        BeforeInvocationEventHandler(callback: { event in
            // modify the prompt
            event.prompt.segments.append(
                .text(.init(content: "Always start your response with ⭐."))
            )
        })
    )
}

private func setUpStateAccessing(_ agent: Agent) {
    agent.addHook(
        BeforeInvocationEventHandler(callback: { event in
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
                event.agent.agentState["prompt_count"]?.asInt() ?? 0 + 1
            event.agent.agentState["prompt_count"] = .number(
                Double(toolCount)
            )
        })
    )
}

func beforeInvocationHook(
    stream: Bool = false,
    example: BeforeInvocationExample
)
    async throws
{
    let agent = Agent(
        tools: [],
        instruction: .init("You are a helpful assistant.")
    )

    switch example {
    case .stateAccessing:
        setUpStateAccessing(agent)
    case .cancellation:
        setupCancellation(agent)
    case .promptMutation:
        setupPromptMutation(agent)
    }

    stream ? try await testStream(agent) : try await testRespond(agent)
}
