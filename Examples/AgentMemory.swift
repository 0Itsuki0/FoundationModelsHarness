//
//  AgentMemory.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/24.
//

import FoundationModels
import FoundationModelsHarness

private let prompt = "Which pokemon do i like the most?"

private func testStream(_ agent: Agent) async {
    await printStream(agent.streamResponse(to: prompt))
    printHistory(agent.history)
}

private func testRespond(_ agent: Agent) async {
    let _ = await agent.respond(to: prompt)
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

func agentMemory(stream: Bool = false) async {
    let store = InMemoryMemoryStore(
        storeConfiguration: .init(
            searchConfiguration: .init(useSameCategoryFallback: true)
        )
    )

    do {
        try await store.addMemories(
            testEntries.map({
                MemoryEntry(
                    category: $0.category,
                    fact: $0.fact,
                    embeddings: nil
                )
            })
        )

        let config = AgentMemoryConfiguration(
            store: store,
            //            autoExtraction: .init(
            //                extractor: LanguageModelExtractor(
            //                    schema: String.self.generationSchema,
            //                    buildPrompt: { _ in Prompt {} }
            //                ),
            //                turnBufferCount: 5,
            //                onExtraction: { _ in }
            //            ),
            addMemoryToolConfig: .init(enabled: false),
            searchMemoryToolConfig: .init(enabled: true)
        )

        let agent = await Agent(
            tools: [.init(tool: GreetingTool(), delegate: true)],
            instruction: .init("You are a helpful assistant."),
            memoryConfiguration: config
        )

        stream ? await testStream(agent) : await testRespond(agent)
    } catch {
        print("Error: ", error)
    }
}
