//
//  main.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import FoundationModels
import FoundationModelsHarness
import SwiftUI

do {
    let agent = Agent(
        tools: [.init(tool: GreetingTool(), delegate: false)],
        instruction: .init("You are a helpful assistant.")
    )

    agent.addHook(
        BeforeToolCallEventHandler(callback: { event in
            event.agent.invocationState["before called"] = true

            // cancel the tool call
            // event.cancel = .init(stringLiteral: "failed to greet. Do it yourself.")

            // modify tool calls
            event.toolCall.toolName = GreetingTool().name
            let argument = GreetingTool.Arguments(name: "⭐⭐itsuki⭐⭐")
            event.toolCall.arguments = argument.generatedContent
        })
    )

    // let response = try await agent.respond(to: "hello.")
    // print("response: ", response)

    // testing stream
    try await printStream(agent.streamResponse(to: "greet itsuki"))
    try await printStream(
        agent.streamResponse(to: "what's your last tool use?")
    )

    print("---Session History---")
    printHistory(agent.transcript.history)
    print("------")

} catch {
    print("error: ", error)
}
