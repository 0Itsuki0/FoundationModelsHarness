//
//  InMemoryMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

import FoundationModels

public actor InMemoryMemoryStore: MemoryStore {
    private let baseStore: BaseMemoryStore

    public init(storeConfiguration: MemoryStoreConfiguration = .init()) {
        self.baseStore = BaseMemoryStore(
            storeConfiguration: .init(),
            existingMemories: [],
        )
    }

    public func addMemory(_ memory: MemoryEntryPartial) async -> AddMemoryResult
    {
        return await baseStore.addMemory(memory)
    }

    public func searchMemory(_ searchQuery: MemorySearchInput)
        async -> [MemorySearchResult]
    {
        return await baseStore.searchMemory(searchQuery)
    }

    public func addMemories(_ memories: [MemoryEntry]) async {
        let _ = await baseStore.addMemories(memories)
    }

    public func deleteMemories(_ memories: [MemoryEntry.ID]) async {
        await baseStore.deleteMemories(memories)
    }
}
