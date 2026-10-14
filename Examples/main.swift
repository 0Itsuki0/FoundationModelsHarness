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
        AfterToolCallEventHandler(callback: { event in
//            if event.attemptCount <= 3 {
//                event.retry = true
//                return
//            }
            event.endTurn = "end!"
        })
    )

    let _ = try await agent.respond(to: "hello. greet itsuki.")
    //    print("response: ", response)

    // testing stream
    //    try await printStream(agent.streamResponse(to: "hello. greet itsuki."))
    //    try await printStream(
    //        agent.streamResponse(to: "how's going?")
    //    )
    //
    printHistory(agent.transcript.history)

} catch {
    print("error: ", error)
}
