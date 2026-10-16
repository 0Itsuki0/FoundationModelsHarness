//
//  AfterInvocation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/16.
//

import FoundationModels
import FoundationModelsHarness

/// After invocation call hook:  Event triggered at the end of an agent request.
///
/// Example:
/// - `stateAccessing`: Read/write states that ca also be read/write from the tools / other hook handlers
/// - `cancellation`: Cancel the model invocation with a message
/// - `promptMutation`: change the prompt
enum AfterInvocationExample {
    case retry
    case resume
}

private func testStream(_ agent: Agent) async throws {
    await printStream(
        agent.streamResponse(to: "Hello", invocationState: ["resume": true])
    )
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async throws {
    let _ = await agent.respond(
        to: "Hello",
        invocationState: ["resume": true]
    )
    printHistory(agent.history)
}

private func setupRetry(_ agent: Agent) {
    agent.addHook(
        AfterInvocationEventHandler(callback: { event in
            if event.attemptCount == 1 {
                event.retry = true
            }
        })
    )
}

private func setupResume(_ agent: Agent) {
    agent.addHook(
        AfterInvocationEventHandler(callback: { event in
            if event.agent.invocationState["resume"]?.asBool() == true {
                event.resume = Prompt { "how's going?" }
                event.agent.invocationState["resume"] = false
            }
        })
    )
}

func afterInvocationHook(
    stream: Bool = false,
    example: AfterInvocationExample
)
    async throws
{
    let agent = Agent(
        tools: [],
        instruction: .init("You are a helpful assistant.")
    )

    switch example {
    case .resume:
        setupResume(agent)
    case .retry:
        setupRetry(agent)
    }
    stream ? try await testStream(agent) : try await testRespond(agent)
}
