//
//  AfterTools.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModelsHarness

/// After tools hook: triggered after all tools complete execution.
///
/// - set `endTurn` to short-circuit to the invocation output without invoking the model again to generate a final response based on tool output.
private let prompt = "greet itsuki and dan."

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: prompt))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: prompt)
    printHistory(agent.history)
}

private func setupEndTurn(_ agent: Agent) {
    agent.addHook(
        AfterToolsEventHandler(callback: { event in
            let results = event.toolResults.map(\.result).map({ try? $0.get() })
            let failureCount = results.count(where: { $0 == nil })
            event.endTurn = .string(
                "Tools finished. \(results.count - failureCount) success. \(failureCount) failed."
            )
        })
    )
}

func afterToolsHook(stream: Bool = false) async {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: false)],
        instruction: .init("You are a helpful assistant.")
    )

    setupEndTurn(agent)

    stream ? await testStream(agent) : await testRespond(agent)
}
