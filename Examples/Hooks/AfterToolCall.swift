//
//  AfterToolCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

import FoundationModelsHarness

/// After tool call hook: triggered after a tool execution completes.
///
/// - set `retry`to request a retry of the tool call.
/// - mutate `toolResult` to modify or reject the tool output
enum AfterToolCallExample {
    case retry
    case mutate
}

private let prompt = "Hello. Greet itsuki."

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: prompt))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: prompt)
    printHistory(agent.history)
}

private func setupRetry(_ agent: Agent) {
    agent.addHook(
        AfterToolCallEventHandler(callback: { event in
            if event.attemptCount < 2 {
                event.retry = true
            }
        })
    )
}

private func setupResponseMutation(_ agent: Agent) {
    agent.addHook(
        AfterToolCallEventHandler(callback: { event in
            event.toolResult = .failure(ToolCallFailure())
        })
    )
}

private struct ToolCallFailure: Error {}

func afterToolCallHook(stream: Bool = false, example: AfterToolCallExample)
    async
{
    let agent = Agent(
        tools: [.init(tool: GreetingTool())],
        instruction: .init("You are a helpful assistant.")
    )

    switch example {
    case .mutate:
        setupResponseMutation(agent)
    case .retry:
        setupRetry(agent)
    }

    stream ? await testStream(agent) : await testRespond(agent)
}
