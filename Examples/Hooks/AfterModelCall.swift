//
//  AfterModelCall.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModelsHarness

/// After model call hook: triggered after the model invocation completes
///
/// - set `retry`to request a retry of the modal call.
/// - mutate `stopReason` to modify or refuse model's response
enum AfterModelExample {
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
        AfterModelCallEventHandler(callback: { event in
            if event.attemptCount == 1 {
                event.retry = true
            }
        })
    )
}

private func setupResponseMutation(_ agent: Agent) {
    agent.addHook(
        AfterModelCallEventHandler(callback: { event in
            event.stopReason = .endTurn(
                .init(segments: [.text(.init(content: "turn ended"))])
            )
        })
    )
}

func afterModelHook(stream: Bool = false, example: AfterModelExample) async {
    let agent = await Agent(
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
