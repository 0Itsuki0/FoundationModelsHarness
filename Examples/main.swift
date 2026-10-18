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
    AfterToolCallEventHandler(callback: { event in
        if event.attemptCount < 2 {
            event.retry = true
        } else {
            event.toolResult = .failure(NSError(domain: "failed", code: 1))
        }
    })
)

//agent.agentState["app"] = "Test"
//let result = await agent.respond(
//    to: "hello. greet itsuki",
//    invocationState: ["resume": true]
//)
//print("result", result)
////print("response: ", response.rawContent as Any)
//print("-----")
//await agent.respond(to: "how's going")

// testing stream
//await printStream(agent.streamResponse(to: "hello. greet itsuki.", invocationState: ["resume": true]))
//await printStream(
//    agent.streamResponse(to: "how's going?")
//)
//
//printHistory(agent.history)
await afterToolCallHook(stream: true, example: .mutate)


// TODO: -
// 1. after tool call migration to agent loop
// 2. plugin
// 3. implement delegation as plugin
