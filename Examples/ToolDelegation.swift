//
//  ToolDelegation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import FoundationModelsHarness

/// Tool Delegation Example:
///
/// When a tool is configured with `delegate: true`, this package ensures:
/// 1. The agent loop exits immediately after a successful delegation (via endTurn)
/// 2. The delegation tool's content blocks become the final assistant message
/// 3. The delegation tool is the only tool called in the turn

private let prompt = "greet itsuki and dan"

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: prompt))
    await printStream(agent.streamResponse(to: "who did you greet?"))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let response = await agent.respond(to: prompt)
    print("response: ", response)
    let followUp = await agent.respond(to: "who did you greet?")
    print("follow up: ", followUp)
    printHistory(agent.history)
}

func toolDelegation(stream: Bool = false) async {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: true)],
        instruction: .init("You are a helpful assistant.")
    )

    stream ? await testStream(agent) : await testRespond(agent)
}
