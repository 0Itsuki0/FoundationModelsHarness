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
        BeforeToolCallEventHandler(callback: { _ in
            print("before first")
        })
    )

    agent.addHook(
        BeforeToolCallEventHandler(callback: { _ in
            print("before second")
        })
    )
    agent.addHook(
        BeforeToolCallEventHandler(
            callback: { _ in
                print("before system")
            },
            options: .init(order: BuiltInHookOrder.sdkFirst.rawValue)
        )
    )

    agent.addHook(
        AfterToolCallEventHandler(callback: { _ in
            print("After first")
        })
    )

    agent.addHook(
        AfterToolCallEventHandler(callback: { _ in
            print("After second")
        })
    )

    agent.addHook(
        AfterToolCallEventHandler(
            callback: { _ in
                print("After system")
            },
            options: .init(order: BuiltInHookOrder.sdkFirst.rawValue)
        )
    )

    let response = try await agent.respond(to: "hello")
    print("response: ", response)
    print("current transcript history")
    printHistory(agent.transcript.history)

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
