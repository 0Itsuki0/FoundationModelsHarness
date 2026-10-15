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

//    agent.addHook(
//        AfterToolCallEventHandler(callback: { event in
////            if event.attemptCount <= 3 {
////                event.retry = true
////                return
////            }
//            event.endTurn = "end!"
//        })
//    )
    
    agent.addHook(
        BeforeToolCallEventHandler(callback: { event in
            // modify tool calls
            event.toolCall.toolName = GreetingTool().name
            let argument = GreetingTool.Arguments(name: "⭐⭐itsuki⭐⭐")
            event.toolCall.arguments = argument.generatedContent
        })
    )


    let _ = await agent.respond(to: "hello. greet itsuki.")
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
