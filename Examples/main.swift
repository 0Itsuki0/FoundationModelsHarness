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
            event.agent.agentState["123"] = "123"
            event.agent.invocationState["123"] = "test"
            event.toolCall.arguments = try .init(json: "{\"name\": \"⭐⭐user⭐⭐\"}")
            print("before tool call finish")
        })
    )

    let response = try await agent.respond(to: "hello")
    print("response: ", response)
    print("current transcript history")
    printHistory(agent.transcript.history)
//    try await printStream(agent.streamResponse(to: "greet itsuki"))
//    try await printStream(agent.streamResponse(to: "who did you greet?"))
//
//    print("current transcript history")
//    printHistory(agent.transcript.history)

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
