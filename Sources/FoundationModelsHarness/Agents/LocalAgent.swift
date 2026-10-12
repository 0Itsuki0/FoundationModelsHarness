//
//  LocalAgent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

// TODO: - add in other properties: strands-ts/src/types/agent.ts

/// Interface for agents with locally accessible state, messages, tools, and hooks.
///
/// This interface is only for accessing state in hook events.
public struct LocalAgent: Sendable {
    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    ///
    /// Read/write
    @SessionProperty public var agentState: InvocationState

    /// Invocation state accessible to tools and application logic.
    /// Lives for a single invocation.
    /// State is not passed to the model during inference.
    ///
    /// Read/write
    @SessionProperty public var invocationState: InvocationState

    /// The transcript entries excluding the leading instructions entry, if present.
    ///
    /// Read only
    public let history: Transcript.HistoryView
}

extension LocalAgent {
    public typealias SessionProperty = LanguageModelSession.SessionProperty
}
