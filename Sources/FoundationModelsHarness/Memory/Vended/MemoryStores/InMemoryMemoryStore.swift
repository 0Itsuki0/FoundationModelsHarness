//
//  InMemoryMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

import FoundationModels

/// In-memory memory store for testing and debugging
/// Best matching logic: Embeddings with Natural Language Framework + cosine distance
public actor InMemoryMemoryStore: MemoryStore {
    actor MemoryProvider: BaseMemoryStore.MemoryProvider {
        private var memories: [MemoryEntry] = []
        init() {}

        func addMemories(_ memories: [MemoryEntry]) {
            self.upsertMemories(memories)
        }

        func updateMemories(_ memories: [MemoryEntry]) {
            self.upsertMemories(memories)
        }

        private func upsertMemories(_ memories: [MemoryEntry]) {
            var current = self.getMemories()
            current.removeAll(where: { memories.map(\.id).contains($0.id) })
            current.append(contentsOf: memories)
            self.saveMemories(current)
        }

        func deleteMemories(_ memories: [MemoryEntry.ID]) {
            var current = self.getMemories()
            current.removeAll(where: { memories.contains($0.id) })
            self.saveMemories(current)
        }

        func getMemories() -> [MemoryEntry] {
            return self.memories
        }

        private func saveMemories(_ memories: [MemoryEntry]) {
            self.memories = memories
        }
    }

    private let baseStore: BaseMemoryStore

    /// Create a in-memory memory store
    ///
    /// - Parameters:
    ///  - storeConfiguration :memory store configurations
    public init(storeConfiguration: MemoryStoreConfiguration = .init()) {
        self.baseStore = BaseMemoryStore(
            storeConfiguration: storeConfiguration,
            memoryProvider: MemoryProvider()
        )
    }

    // MARK: - MemoryStore Implementation
    public func addMemory(_ memory: MemoryEntryPartial) async -> AddMemoryResult
    {
        return await baseStore.addMemory(memory)
    }
    
    public func searchMemory(_ searchQuery: MemorySearchInput) async
    -> [MemorySearchResult]
    {
        return await baseStore.searchMemory(searchQuery)
    }
    
    // MARK: - CRDU
    public func getMemories() async throws -> [MemoryEntry] {
        try await baseStore.getMemories()
    }
    
    public func addMemories(_ memories: [MemoryEntry]) async throws {
        try await baseStore.addMemories(memories)
    }
    
    public func updateMemories(_ memories: [MemoryEntry]) async throws {
        try await baseStore.updateMemories(memories)
    }
    
    public func deleteMemories(_ memories: [MemoryEntry.ID]) async throws {
        try await baseStore.deleteMemories(memories)
    }
}
