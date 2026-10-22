//
//  StoreConfiguration.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

/// Search configuration to apply when searching for memories matching a `MemorySearchInput`
///
/// - Parameters:
///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
///  - similarityThreshold: Cosine similarity threshold.
///  - topK:Limit the search result to top K matches
public struct MemorySearchConfiguration {

    /// whether to use same category entry when there is no result returned after filtering with `similarityThreshold` and `topK`
    public var useSameCategoryFallback: Bool = true

    /// Cosine similarity threshold.
    /// When defined, any memory entries with a cosine similarity smaller than the threshold will be excluded.
    ///
    /// Recommended value if using Apple's `NaturalLanguage` embeddings: 0.28 ~ 0.5.
    /// 0 itself means orthogonal textbook-definition wise,
    /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a lower similarity than expected.
    public var similarityThreshold: Double?

    /// Limit the search result to top K matches
    public var topK: Int?

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
