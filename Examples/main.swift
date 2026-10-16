//
//  main.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import FoundationModels
import FoundationModelsHarness
import SwiftUI

private struct PromptReceived: Error {
    let prompt: Transcript.Prompt
}

extension Transcript.Entry {
    var asPrompt: Transcript.Prompt? {
        if case .prompt(let value) = self {
            return value
        }
        return nil
    }
}

func segments(from prompt: PromptRepresentable) async -> [Transcript
    .Segment]
{
    let profile = LanguageModelSession.Profile {}.onPrompt {
        throw PromptReceived(prompt: $0)
    }

    let session = LanguageModelSession(profile: profile)
    /// make sure the prompt is preserved even when there is an error calling the model
    session.transcriptErrorHandlingPolicy = .preserveTranscript
    let prompt = prompt.promptRepresentation
    do {
        let _ = try await session.respond(to: prompt)
    } catch {
        if let error = error as? PromptReceived {
            return error.prompt.segments
        }
    }
    /// fallback if the PromptReceived is never caught
    return session.transcript.history.compactMap { $0.asPrompt }.first?
        .segments ?? []
}

//do {
//    let session = LanguageModelSession()
//    let prompt = Prompt {
//        Attachment(imageURL: URL(filePath: "/Users/itsuki/Desktop/pikachu/pikachu.jpg"))
//        "What's in the image"
//    }
//    let segments = await segments(from: prompt)
//    session.transcript.history.append(.prompt(.init(segments: segments)))
//    let response = try await session.respond(to: "")
//    print(response.rawContent)
//} catch {
//    print(error)
//}

//
let agent = Agent(
    tools: [
        .init(tool: GreetingTool(), delegate: false)
    ],
    instruction: .init("You are a helpful assistant.")
)

agent.addHook(
    BeforeInvocationEventHandler(callback: { event in
        //        event.prompt.segments.append(
        //            .text(.init(content: "Always start your response with ⭐."))
        //        )
        //        event.cancel = "Service unavailable"
//        print(
//            """
//            BeforeInvocationEventHandler triggered: 
//            invocationState: \(event.agent.invocationState)
//            agentState: \(event.agent.agentState)
//            history: \(event.agent.history)
//            """
//        )

        event.agent.agentState["app_2"] = "test2"
    })
)

agent.addHook(
    AfterToolCallEventHandler(callback: { event in
        //            if event.attemptCount <= 3 {
        //                event.retry = true
        //                return
        //            }
        //            event.endTurn = "end!"
    })
)

//agent.addHook(
//    BeforeToolCallEventHandler(callback: { event in
//        // modify tool calls
//        event.toolCall.toolName = GreetingTool().name
//        let argument = GreetingTool.Arguments(name: "⭐⭐itsuki⭐⭐")
//        event.toolCall.arguments = argument.generatedContent
//    })
//)

//agent.agentState["app"] = "Test"
//let response = await agent.respond(
//    to: "hello. greet itsuki",
//    invocationState: ["test": 123]
//)
////print("response: ", response.rawContent as Any)
//print("-----")
//await agent.respond(to: "how's going")

// testing stream
await printStream(agent.streamResponse(to: "hello. greet itsuki."))
await printStream(
    agent.streamResponse(to: "how's going?")
)
//
printHistory(agent.history)
