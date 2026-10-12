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
        tools: [.init(tool: GreetingTool(), delegate: true)],
        instruction: .init("You are a helpful assistant.")
    )

    agent.addHook(
        BeforeToolCallEventHandler(callback: { event in
            // modify tool calls
            event.agent.invocationState["before called"] = true

            event.toolCall.toolName = GreetingTool().name
            let argument = GreetingTool.Arguments(name: "⭐⭐itsuki⭐⭐")
            event.toolCall.arguments = argument.generatedContent
        })
    )

    let response = try await agent.respond(to: "hello.")

    print("response: ", response)

    // testing stream
    //    try await printStream(agent.streamResponse(to: "greet itsuki"))
    //    try await printStream(
    //        agent.streamResponse(to: "what's your last tool use?")
    //    )

    print("---Session History---")
    printHistory(agent.transcript.history)
    print("------")

    //
    //    //    try await testRespond(agent)
    //
    //    let session = LanguageModelSession(
    //        transcript: .init(entries: [
    //            .prompt(.init(segments: [.text(.init(content: "Hello. How's going"))]))
    //        ])
    //    )
    //
    //    let response = try await session.respond(prompt: {})
    //    print(response)
    //    print(session.transcript.history)
} catch {
    print("error: ", error)
}
