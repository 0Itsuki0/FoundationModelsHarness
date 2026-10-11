//
//  ToolDelegation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import FoundationModelsHarness

private func testStream(_ agent: Agent) async throws {
    try await printStream(agent.streamResponse(to: "greet itsuki"))
    try await printStream(agent.streamResponse(to: "who did you greet?"))
}

private func testRespond(_ agent: Agent) async throws {
    let response = try await agent.respond(to: "greet itsuki")
    print("response: ", response)
    print("current transcript history")
    printHistory(agent.transcript.history)
    let followUp = try await agent.respond(to: "who did you greet?")
    print("follow up: ", followUp)
}

func toolDelegation(stream: Bool = false) async throws {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: true)],
        instruction: .init("You are a helpful assistant.")
    )

    stream ? try await testStream(agent) : try await testRespond(agent)
}
