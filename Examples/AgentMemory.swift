//
//  AgentMemory.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/24.
//

import Foundation
import FoundationModels
import FoundationModelsHarness
import SQLiteStore

private let first = "Which pokemon do i like the most?"
// Not true! It is just for testing. I only like Pikachu!
private let second = "It actually changed to ditto!"

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: first))
    await printStream(agent.streamResponse(to: second))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: first)
    let _ = await agent.respond(to: second)
    printHistory(agent.history)
}

private let testEntries: [MemoryEntryPartial] = {
    let facts: [(MemoryCategory, String)] = [
        /// About the user
        (
            .preferences,
            "The user prefers concise answers without lengthy explanations."
        ),
        (
            .preferences,
            "The user's favorite pokemon is pikachu."
        ),
        (.preferences, "Do not add third-party dependencies to the project."),
        (
            .preferences,
            "The user said to only do exactly what is asked and not change unrelated code."
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
            "Add automatic clean up of memories that have not been used for 30 days."
        ),
    ]
    return facts.map {
        .init(
            category: $0.0,
            fact: $0.1,
        )
    }
}()

func agentMemory(stream: Bool = false, ) async {

    let url = URL.temporaryDirectory.appending(path: "memory.db")
    try? FileManager.default.removeItem(at: url)

    do {
        /// Other available stores: `InMemoryMemoryStore`,  `FileMemoryStore`.
        let store = try SQLiteMemoryStore(
            url: url,
            storeConfiguration: .init(
                searchConfiguration: .init(useSameCategoryFallback: true),
                eraseDatabaseOnSchemaChange: true
            )
        )

        try await store.addMemories(testEntries)

        let config = AgentMemoryConfiguration(
            store: store,
            autoExtraction: .init(
                extractor: LanguageModelExtractor(),
                turnBufferCount: 2,
                onExtraction: { result in
                    print(result)
                    guard let result = try? result.get(),
                        let result = try? result.value(
                            LanguageModelExtractor.DefaultExtractionResult.self
                        )
                    else {
                        return
                    }
                    do {
                        try await store.addMemories(result.add)
                        try await store.deleteMemories(
                            result.remove.map(Int64.init)
                        )
                    } catch {
                        print(error)
                    }
                }
            ),
            addMemoryToolConfig: .init(enabled: false),
            searchMemoryToolConfig: .init(
                enabled: true,
                additionalInstruction: .init(
                    MemoryToolDefault.searchToolSystemInjection()
                )
            )
        )

        let agent = await Agent(
            tools: [],
            instruction: .init("You are a helpful assistant."),
            memoryConfiguration: config
        )

        stream ? await testStream(agent) : await testRespond(agent)

        // A little wait for the extraction to finish.
        try? await Task.sleep(for: .milliseconds(3000))

        print(try await store.getMemories())
    } catch {
        print("Error: ", error)
    }
}
