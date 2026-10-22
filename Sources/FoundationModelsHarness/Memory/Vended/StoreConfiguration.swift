//
//  StoreConfiguration.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/22.
//

/// Search configuration to apply when searching for memories matching a `MemorySearchInput`
///
/// - Parameters:
///  - useSameCategoryFallback: whether to use same category entry when there is no result returned after filtering with `distanceThreshold` and `topK`
///  - distanceThreshold: Cosine distance threshold.
///  - topK:Limit the search result to top K matches
public struct MemorySearchConfiguration {

    /// whether to use same category entry when there is no result returned after filtering with `distanceThreshold` and `topK`
    public var useSameCategoryFallback: Bool = true

    /// Cosine distance threshold.
    /// When defined, any memory entries with a cosine distance larger than the threshold will be excluded.
    ///
    /// Recommended value if using Apple's `NaturalLanguage` embeddings: 1.0 ~ 1.2.
    /// 1.0 itself means orthogonal textbook-definition wise,
    /// However,NaturalLanguage embedding seems to weight more on repetitive phrases and usually result in a larger distance than expected.
    public var distanceThreshold: Double?

    /// Limit the search result to top K matches
    public var topK: Int?

    public init(
        useSameCategoryFallback: Bool = true,
        distanceThreshold: Double? = nil,
        topK: Int? = nil
    ) {
        self.useSameCategoryFallback = useSameCategoryFallback
        self.distanceThreshold = distanceThreshold
        self.topK = topK
    }
}
