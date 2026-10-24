//
//  LocalAgent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Snapshot of an agent with accessible state, messages, and configurations
/// This snapshot is available in all hooks' callbacks
public final class AgentSnapshot {

    /// Snapshot of Agent's current configuration.
    public struct ConfigurationSnapshot {

        /// Currently registered tools.
        public let tools: [ToolConfig]

        /// Package property for access to all parameters
        let _plugins: [RegisteredPlugin]

        /// Currently register plugins
        public var plugins: [any Plugin] { _plugins.map(\.plugin) }

        /// Currently registered hooks
        public let hooks: [any HookEventHandler]

        /// currently used system instruction
        public let instruction: Instructions

        init(session: LanguageModelSession) {
            self.tools = session.properties.tools
            self.hooks = session.properties.hookRegistry.registeredHooks
            self._plugins = session.properties.pluginRegistry.plugins
            self.instruction = session.properties.instruction
        }

    }

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

    /// Current Agent Configurations
    public let configuration: ConfigurationSnapshot

    init(session: LanguageModelSession) {
        self.session = session
        /// assign at `init` in case `history` and `tools` are modified else where.
        self.history = session.transcript.history
        self.configuration = ConfigurationSnapshot(session: session)
    }
}
