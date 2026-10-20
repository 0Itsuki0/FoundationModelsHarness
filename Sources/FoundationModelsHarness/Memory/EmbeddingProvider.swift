//
//  EmbeddingProvider.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/20.
//

import NaturalLanguage

public protocol EmbeddingProvider {
    func embeddings(for query: String) -> [Double]?
}

//public protocol SimilarityProvider {
//    
//}

public class NLEmbeddingProvider {
    
}
