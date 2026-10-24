//
//  backup.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/20.
//

import Accelerate
import FoundationModels
import FoundationModelsHarness
import NaturalLanguage
import SwiftUI

let harnessTestEntries: [MemoryEntry] = {
    let facts: [(FoundationModelsHarness.MemoryCategory, String)] = [
        /// About the user
        (.identity, "The user's name is Itsuki."),
        (
            .identity,
            "The user is an iOS developer based in Tokyo, timezone JST (UTC+9)."
        ),
        (
            .preferences,
            "The user prefers concise answers without lengthy explanations."
        ),
        (
            .preferences,
            "Never commit or push to git without the user's explicit permission."
        ),
        (.preferences, "Do not add third-party dependencies to the project."),
        /// About the work
        (
            .project,
            "FoundationModelsHarness is a Swift package providing agents, tools, memory and goal plugins for Foundation Models."
        ),
        (
            .project,
            "Long-term memory uses NLEmbedding sentence embeddings with cosine distance for similarity search."
        ),

        /// About the world
        (.people, "Ken owns the backend API that the iOS app talks to."),
        /// About time
        (
            .tasks,
            "On 2026-10-08 the user started the FoundationModelsHarness project."
        ),
        (
            .tasks,
            "On 2026-10-19 a tool delegation bug was fixed when a delegated tool is added or removed."
        ),
        (
            .tasks,
            "Add automatic clean up of memories that have not been used for 30 days."
        ),
    ]
    return facts.map {
        .init(
            category: $0.0,
            fact: $0.1,
            embeddings: NLEmbedding.sentenceEmbedding(for: .english)?.vector(
                for: $0.1
            )
        )
    }
}()

private let testingQuery: [String] = [
    /// paraphrases of stored facts (expected: close match)
    "What is the user's name?",
    "Where does the user live and what timezone are they in?",
    "Does the user like short or long responses?",
    "Which programming language does the user use?",
    "Am I allowed to push commits to git?",
    "Can I add an external library to the package?",
    "What is FoundationModelsHarness?",
    "How does memory search work?",
    "Why NLEmbedding instead of NLContextualEmbedding?",
    "How do I run the example?",
    "Is NLEmbedding thread safe?",
    "Who is responsible for the backend?",
    "Where are the Foundation Models docs?",
    "How large is the on-device model's context window?",
    "When did the project start?",
    "What bug was fixed recently?",
    "What are the open tasks?",

    /// opposites of stored facts (expected: large distance)
    "The user prefers long, detailed explanations.",
    "Feel free to commit and push to git anytime.",

    /// unrelated (expected: no match)
    "What's the weather like in Paris today?",
    "Recommend a good pasta recipe.",
]

//print(calculateCosineDistance(v1, b: v2))

//let store = InMemoryMemoryStore(memories: testEntries)
//let addTool = AddMemoryTool(call: { argument in
//    await store.addMemory(argument)
//    return true
//})
//let searchTool = SearchMemoryTool(call: { argument in
//    return await store.searchMemory(argument)
//})
//
//do {
//    let session = LanguageModelSession(
//        model: SystemLanguageModel(),
//        tools: [
//            addTool, searchTool,
//        ],
//        instructions: nil
//    )
//    for query in testingQuery {
//        print("-----")
//        let response = try await session.respond(to: query)
//        printHistory(session.transcript.history)
//        session.transcript.history.removeAll()
//    }
//    //    let _ = try await session.respond(
//    //        to: "My favorite pokemon is pikachu. this is important"
//    //    )
//    //    let _ = try await session.respond(
//    //        to: "My name is itsuki. this is important"
//    //    )
//    //    let _ = try await session.respond(
//    //        to: "what's my best friend's name?"
//    //    )
//    //    print(response.content)
//
//    //    let prompt = Prompt {
//    //        Attachment(imageURL: URL(filePath: "/Users/itsuki/Desktop/pikachu/pikachu.jpg"))
//    //        "What's in the image"
//    //    }
//    //    let segments = await segments(from: prompt)
//    //    session.transcript.history.append(.prompt(.init(segments: segments)))
//    //    let response = try await session.respond(to: "")
//    //    print(response.rawContent)
//
//} catch {
//    print(error)
//}

//if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english) {
//    let sentence = "The user's name is Itsuki."
//
//
//    let distance = sentenceEmbedding.distance(between: sentence, and: "The user is named Itsuki.")
//    print(distance.description)
//}

//
//let agent = await Agent(
//    tools: [
////        .init(tool: GreetingTool(), delegate: true)
//    ],
//    instruction: .init("You are a helpful assistant.")
//)
//agent.addTool(.init(tool: GreetingTool(), delegate: true))

//agent.addHook(
//    AfterToolCallEventHandler(callback: { event in
//        if event.attemptCount < 2 {
//            event.retry = true
//        } else {
//            event.toolResult = .failure(NSError(domain: "failed", code: 1))
//        }
//    })
//)

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

//await toolDelegation()

//
