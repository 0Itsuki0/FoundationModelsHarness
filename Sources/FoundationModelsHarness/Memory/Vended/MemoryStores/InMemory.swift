//
//  InMemoryMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

import NaturalLanguage

private let testEntries: [MemoryEntry] = {
    let facts: [(Category, String)] = [
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

public actor InMemoryMemoryStore {
    private let baseStore: BaseMemoryStore

    public init(storeConfiguration: MemoryStoreConfiguration = .init()) {
        self.baseStore = BaseMemoryStore(
            storeConfiguration: .init(),
            existingMemories: testEntries
        )
    }

    public func addMemory(_ memory: MemoryEntryPartial) -> AddMemoryResult {
        return baseStore.addMemory(memory)
    }

    public func searchMemory(_ searchQuery: MemorySearchInput)
        -> [MemorySearchResult]
    {
        return baseStore.searchMemory(searchQuery)
    }
}
