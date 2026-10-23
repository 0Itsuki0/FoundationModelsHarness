//
//  FileMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/23.
//

import Foundation
import FoundationModels

/// File memory store to store entries in a JSON file.
public actor FileMemoryStore: MemoryStore {
    private let baseStore: BaseMemoryStore
    private let fileURL: URL

    private var storeUpdateTask: Task<Void, Never>?

    /// Create a file memory store
    ///
    /// - Parameters:
    ///  - fileURL: File URL to save the memory entry
    public init(
        fileURL: URL = URL.applicationDirectory.appending(path: "memory.json"),
        storeConfiguration: MemoryStoreConfiguration = .init(),
        existingMemories: [MemoryEntry] = []
    ) {
        self.fileURL = fileURL
        let baseStore = BaseMemoryStore(
            storeConfiguration: .init(),
            existingMemories: [],
        )

        self.baseStore = baseStore

        Task {
            await self.setupStoreUpdateListener()
        }
    }

    private func setupStoreUpdateListener() {
        self.storeUpdateTask = Task {
            for await event in baseStore.storeUpdateStream {
                self.handleStoreUpdate(event)
            }
        }
    }

    public func addMemory(_ memory: MemoryEntryPartial) async -> AddMemoryResult
    {
        return await baseStore.addMemory(memory)
    }

    public func searchMemory(_ searchQuery: MemorySearchInput) async
        -> [MemorySearchResult]
    {
        return await baseStore.searchMemory(searchQuery)
    }

    public func addMemories(_ memories: [MemoryEntry]) async {
        let _ = await baseStore.addMemories(memories)
    }

    public func deleteMemories(_ memories: [MemoryEntry.ID]) async {
        await baseStore.deleteMemories(memories)
    }

    private func handleStoreUpdate(
        _ event: BaseMemoryStore.MemoryStoreUpdate
    ) {
        print(#function, event)
    }
}
