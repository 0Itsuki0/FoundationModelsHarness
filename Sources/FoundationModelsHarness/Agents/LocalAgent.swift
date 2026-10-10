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
/// This interface is exported for typing purposes only (e.g. in {@link ToolContext},
/// hook events, and {@link Plugin.initAgent}). The Strands SDK is responsible for
/// providing all implementations.
public struct LocalAgent: Sendable {
    @SessionProperty
    public var agentState: StateStore

    @SessionProperty
    public var invocationState: StateStore

    @SessionProperty
    public var history: Transcript.HistoryView
}

extension LocalAgent {
    public typealias SessionProperty = LanguageModelSession.SessionProperty
}
