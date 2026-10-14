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
        BeforeModelCallEventHandler(callback: { event in
            event.prompt.segments.append(
                .text(.init(content: "Always start your response with ⭐."))
            )
        })
    )

    //    let response = try await agent.respond(to: "hello.")
    //    print("response: ", response)

        try await beforeToolCallHook(stream: true, example: .toolCallMutation)

    // testing stream
//    try await printStream(agent.streamResponse(to: "hello. greet itsuki."))
//    try await printStream(
//        agent.streamResponse(to: "how's going?")
//    )
//
//        printHistory(agent.transcript.history)

} catch {
    print("error: ", error)
}
