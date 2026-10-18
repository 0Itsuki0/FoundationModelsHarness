//
//  LocalAgent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Interface for agents with locally accessible state, messages, and tools.
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
    public let history: Transcript.HistoryView

    /// Currently registered tools.
    public let tools: [ToolConfig]

    init(session: LanguageModelSession) {
        self.session = session
        /// assign at `init` in case `history` and `tools` are modified else where.
        self.history = session.transcript.history
        self.tools = session.properties.tools
    }
}
