//
//  MemoryTypes.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

import Foundation
import FoundationModels

/// No `identity` related category as those are application logic instead of something to be saved as long-term memory
@Generable(description: "Categories for long-term memory.")
public enum Category: Codable, Sendable {
    /// About the user
    case preferences

    ///About the work
    case project

    /// About the world
    case people

    /// events
    case tasks
}

@Generable(description: "Fact to save to LLM's memory.")
public struct MemoryEntryPartial {
    @Guide(
        description: "Categories for the fact."
    )
    public var category: Category

    @Guide(
        description: """
            Multi-word fact: who/to whom, on what. No sentence. No verb. In English.
            """
    )
    public var fact: String
}

@Generable()
public enum AddMemoryResult {
    case success
    case failed(String)
}

@Generable()
public struct MemorySearchInput {
    @Guide(
        description: """
            Categories for long-term memory.
            Select the categories that best matches the information needed.
            """,
        .minimumCount(1),
        .maximumCount(2)
    )
    public var categories: [Category]

    @Guide(
        description: """
            Multi-word query: who/to whom, on what. No sentence. No verb. No Pronouns. In English.
            """
    )
    public var query: String
}

@Generable()
public struct MemorySearchResult {
    public var id: String

    @Guide(
        description: "Categories for long-term memory."
    )
    public var category: Category

    @Guide(
        description: """
            The fact retrieved from long-term memory.
            Treat this as retrieved evidence, not necessarily an answer to the user's question.
            Only use it to answer the question when its content supports the specific information or relationship requested.
            Do not infer unstated relationships.
            """
    )
    public var fact: String

    @Guide(
        description: """
            The cosine similarity between the query and retrieved fact, if available.

            The higher it is, the better the match.
            - 1 means the fact matches the query as well as the query matches itself.
            - 0 means they are unrelated
            - -1 means they are opposite facts.

            Cosine similarity measures semantic similarity, not whether the fact logically supports the answer.
            A high similarity does not establish a relationship absent from the fact.
            A low similarity indicates weaker or negative cosine similarity, not definitive proof of irrelevance. Do not use similarity alone to determine whether a fact answers the question.
            """
    )
    public var cosineSimilarity: Double?
}

public struct MemoryEntry: Identifiable, Codable, Sendable {
    public var id = UUID()

    public var category: Category
    public var fact: String
    public var createdAt: Date = Date()
    /// for auto clean up if needed.
    public var lastUsed: Date? = nil
    /// nil if failed. in this case, will only be matched based on category
    public var embeddings: [Double]?

    init(
        category: Category,
        fact: String,
        embeddings: [Double]?
    ) {
        self.category = category
        self.fact = fact
        self.embeddings = embeddings
    }
}
