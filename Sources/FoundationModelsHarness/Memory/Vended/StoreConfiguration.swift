//
//  StoreConfiguration.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

/// Common configuration for the vended memory stores
public struct MemoryStoreConfiguration {
    /// Search configuration to apply when searching for memories matching a `MemorySearchInput`.
    /// aka: there is enough similarity to the query.
    public var searchConfiguration: MemorySearchConfiguration = .init(
        similarityThreshold: 0.28
    )

    /// Add a memory as a new entry only if the cosine similarity to every existing entry is smaller than `addThresholdSimilarity`,
    /// aka: there is enough distinction to the existing entries.
    /// `nil` to always add the memory.
    ///
    /// - Similarity = 1: The vectors point in the exact same direction. They are perfectly identical in orientation.
    /// - Similarity > 0: The vectors point in a similar direction. The angle between them is acute (less than 90 degrees).
    /// - Similarity = 0: The vectors are orthogonal (perpendicular). They are completely independent and share no relationship or directional similarity (a 90-degree angle).
    /// - Similarity < 0: The vectors point in opposite directions. The angle between them is obtuse (greater than 90 degrees).
    /// - Similarity = -1: The vectors point in the exact opposite direction (a 180-degree angle).
    ///
    /// However,`NaturalLanguage` embedding seems to weight more on repetitive phrases and usually result in a lower similarity than expected.
    public var addThresholdSimilarity: Double?

    /// A memory will be removed if its similarity to the new entry is smaller than `removeThresholdSimilarity`,
    /// aka: they point in the (nearly) opposite direction.
    /// `nil` to never remove existing memory while add new entry
    public var removeThresholdSimilarity: Double?

    /// Days before removing an unused entry from the memory store automatically.
    /// `nil` to never remove unused entries
    public var maxUnusedDays: Int? = 30

    /// Create a memory store configuration for vended stores
    ///
    /// - Parameters:
    ///  - searchConfiguration: Search configuration to apply when searching for memories matching a `MemorySearchInput`
    ///  - addThresholdSimilarity: Add a memory as a new entry only if the cosine similarity to every existing entry is smaller than the threshold.
    ///  - removeThresholdSimilarity: A memory will be removed if its similarity to the new entry is smaller than threshold
    ///  - maxUnusedDays: Days before removing an unused entry from the memory store automatically
    public init(
        searchConfiguration: MemorySearchConfiguration = .init(topK: 10),
        addThresholdSimilarity: Double? = 0.5,
        removeThresholdSimilarity: Double? = -0.9,
        maxUnusedDays: Int? = 30
    ) {
        self.addThresholdSimilarity = addThresholdSimilarity
        self.searchConfiguration = searchConfiguration
        self.removeThresholdSimilarity = removeThresholdSimilarity
        self.maxUnusedDays = maxUnusedDays
    }
}

/// search configuration to apply when searching for memories matching a `MemorySearchInput`.
///
/// - Parameters:
///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
///  - similarityThreshold: Cosine similarity threshold where entries with a value smaller than the threshold will be excluded
///  - topK:Limit the search result to top K matches
public struct MemorySearchConfiguration {

    /// whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
    public var useSameCategoryFallback: Bool = true

    /// Cosine similarity threshold, ranging from -1 to 1.
    /// When defined, any memory entries with a similarity smaller than the threshold will be excluded.
    ///
    /// Recommended value if using Apple's `NaturalLanguage` embeddings: 0.28 ~ 0.5.
    /// 0 itself means orthogonal textbook-definition wise,
    /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a lower similarity than expected.
    public var similarityThreshold: Double?

    /// Limit the search result to top K matches
    public var topK: Int?

    /// Create Search configuration to apply when searching for memories matching a `MemorySearchInput`
    ///
    /// - Parameters:
    ///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
    ///  - similarityThreshold: Cosine similarity threshold where entries with a value smaller than the threshold will be excluded
    ///  - topK:Limit the search result to top K matches
    public init(
        useSameCategoryFallback: Bool = true,
        similarityThreshold: Double? = nil,
        topK: Int? = nil
    ) {
        self.useSameCategoryFallback = useSameCategoryFallback
        self.similarityThreshold = similarityThreshold
        self.topK = topK
    }
}
