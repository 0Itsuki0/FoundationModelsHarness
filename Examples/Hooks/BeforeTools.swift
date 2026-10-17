//
//  BeforeTools.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModelsHarness

/// Before tools hook: triggered before executing tools.
///
/// - set `cancel` to cancel all tool calls.
private let prompt = "greet itsuki and dan."

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: prompt))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: prompt)
    printHistory(agent.history)
}

private func setupCancellation(_ agent: Agent) {
    agent.addHook(
        BeforeToolsEventHandler(callback: { event in
            if event.toolCalls.count > 1 {
                event.cancel = "one tool at a time."
            }
        })
    )
}

func beforeToolsHook(stream: Bool = false) async {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: false)],
        instruction: .init("You are a helpful assistant.")
    )

    setupCancellation(agent)

    stream ? await testStream(agent) : await testRespond(agent)
}
