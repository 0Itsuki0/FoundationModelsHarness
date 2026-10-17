//
//  BeforeModelCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModelsHarness

/// Before model call hook: triggered just before the model is invoked.
///
/// - set `cancel` to cancel a model call, for example, in the case of a budget reached.
private let first = "Hello. Greet user."
private let second = "How's going."

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: first))
    await printStream(agent.streamResponse(to: second))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: first)
    let _ = await agent.respond(to: second)
    printHistory(agent.history)
}

private func setupCancellation(_ agent: Agent) {
    agent.addHook(
        BeforeModelCallEventHandler(callback: { event in
            if event.agent.history.count > 4 {
                event.cancel = "turn limit reached."
            }
        })
    )
}

func beforeModelHook(stream: Bool = false) async {
    let agent = Agent(
        tools: [.init(tool: GreetingTool())],
        instruction: .init("You are a helpful assistant.")
    )

    setupCancellation(agent)

    stream ? await testStream(agent) : await testRespond(agent)
}
