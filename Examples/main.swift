//
//  main.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import FoundationModels
import FoundationModelsHarness
import SwiftUI

struct GreetingTool: Tool {
    let name = "greet"
    let description = "greet a name."

    @SessionProperty(\.agentState)
    var appState

    @SessionProperty(\.invocationState)
    var invocationState

    @SessionProperty(\.history)
    var history

    @Generable
    struct Arguments {
        @Guide(description: "The name to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        print("tool call function")
        return "Hello \(arguments.name)"
    }
}

func testStream(_ agent: Agent) async throws {
    try await printStream(agent.streamResponse(to: "greet itsuki"))
    try await printStream(agent.streamResponse(to: "who did you greet?"))
}

func printStream(_ stream: AsyncThrowingStream<AgentStreamEvent, Error>)
    async throws
{
    var printed = ""
    for try await snapshot in stream {
        switch snapshot {
        case .contentUpdate(rawContent: let raw, _):
            let content: String = (try? raw.value()) ?? "Conversion failed"
            print(content.dropFirst(printed.count), terminator: "")
            printed = content
        case .delegatedToolOutput(let output):
            print("tool output: ", output)
        }
    }
    print()
}

func testRespond(_ agent: Agent) async throws {
    let response = try await agent.respond(to: "greet itsuki")
    print("response: ", response)
    print("current transcript history", agent.transcript.history)
    let followUp = try await agent.respond(to: "who did you greet?")
    print("follow up: ", followUp)
}

do {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: true)],
        instruction: .init("You are a helpful assistant.")
    )

    try await testRespond(agent)
} catch {
    print("error: ", error)
}
