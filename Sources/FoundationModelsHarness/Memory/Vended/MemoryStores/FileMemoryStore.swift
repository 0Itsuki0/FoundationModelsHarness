//
//  FileMemoryStore.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/23.
//

import Foundation
import FoundationModels

/// File memory store to store entries in a JSON file.
/// Best matching logic: Embeddings with Natural Language Framework + cosine distance
public actor FileMemoryStore: MemoryStore {
    actor MemoryProvider: BaseMemoryStore.MemoryProvider {
        private let fileURL: URL
        private let encoder = JSONEncoder()
        private let decoder = JSONDecoder()

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func addMemories(_ memories: [MemoryEntry]) throws {
            try self.upsertMemories(memories)
        }

        func updateMemories(_ memories: [MemoryEntry]) throws {
            try self.upsertMemories(memories)
        }

        private func upsertMemories(_ memories: [MemoryEntry]) throws {
            var current = try self.getMemories()
            current.removeAll(where: { memories.map(\.id).contains($0.id) })
            current.append(contentsOf: memories)
            try self.saveMemories(current)
        }

        func deleteMemories(_ memories: [MemoryEntry.ID]) throws {
            var current = try self.getMemories()
            current.removeAll(where: { memories.contains($0.id) })
            try self.saveMemories(current)
        }

        func getMemories() throws -> [MemoryEntry] {
            guard FileManager.default.fileExists(atPath: fileURL.path()) else {
                return []
            }
            let data = try Data(contentsOf: fileURL)
            let memories = try self.decoder.decode(
                [MemoryEntry].self,
                from: data
            )
            return memories
        }

        private func saveMemories(_ memories: [MemoryEntry]) throws {
            let data = try encoder.encode(memories)
            try data.write(to: fileURL)
        }
    }

    private let baseStore: BaseMemoryStore
    private let fileURL: URL

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private var storeUpdateTask: Task<Void, Never>?

    /// Create a file memory store
    ///
    /// - Parameters:
    ///  - fileURL: File URL to save the memory entry
    ///  - storeConfiguration :memory store configurations
    public init(
        fileURL: URL = URL.applicationDirectory.appending(path: "memory.json"),
        storeConfiguration: MemoryStoreConfiguration = .init(),
        existingMemories: [MemoryEntry] = []
    ) {
        self.fileURL = fileURL
        self.baseStore = BaseMemoryStore(
            storeConfiguration: storeConfiguration,
            memoryProvider: MemoryProvider(fileURL: fileURL)
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
