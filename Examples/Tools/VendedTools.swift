//
//  VendedTools.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/11/01.
//

import Foundation
import FoundationModelsHarness

let chartPrompt = """
    Create a line chart and a point chart for the following data.
    - category: "A", value: 5
    - category: "B", value: 9
    - category: "C", value: 7
    """

private func testStream(_ agent: Agent, prompt: String) async {
    await printStream(agent.streamResponse(to: prompt))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent, prompt: String) async {
    let response = await agent.respond(to: prompt)
    printHistory(agent.history)
}

func createChart(stream: Bool = false) async {
    let agent = await Agent(
        tools: [
            .init(
                tool: CreateChartTool(outputDirectory: URL.temporaryDirectory),
                delegate: false
            )
        ],
        instruction: .init("")
    )

    stream
        ? await testStream(agent, prompt: chartPrompt)
        : await testRespond(agent, prompt: chartPrompt)
}
