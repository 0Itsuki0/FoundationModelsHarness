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
public final class AgentSnapshot: Sendable {
    private let session: LanguageModelSession

    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    ///
    /// Read/write
    public var agentState: AgentState {
        get {
            session.properties.agentState
        }
        set {
            session.properties.agentState = newValue
        }
    }

    /// Invocation state accessible to tools and application logic.
    /// Lives for a single invocation.
    /// State is not passed to the model during inference.
    ///
    /// Read/write
    public var invocationState: InvocationState {
        get {
            session.properties.invocationState
        }
        set {
            session.properties.invocationState = newValue
        }
    }

    /// The transcript entries excluding the leading instructions entry, if present.
    ///
    /// Read only
    public let history: Transcript.HistoryView

    init(session: LanguageModelSession, history: Transcript.HistoryView) {
        self.session = session
        self.history = history
    }
}
