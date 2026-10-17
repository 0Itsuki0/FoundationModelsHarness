//
//  HookEventType.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

// TODO: - add other types
/// https://strandsagents.com/docs/user-guide/sdk/agents/hooks-events/#available-events
public enum HookEventType: Sendable, Hashable, Equatable {
    /// Triggered just before the model is invoked, aka: before messages are sent to the model for inference
    case beforeInvocation

    /// Triggered just before the model is invoked.
    case beforeModelCall
    
    case beforeTools

    /// Triggered just before a tool is executed, aka: before `Tool.call(arguments:)` is called.
    case beforeToolCall

    /// Triggered after tool invocation completes. Uses reverse callback ordering.
    case afterToolCall
    
    case afterTools

    /// Triggered at the end of an agent request. Uses reverse callback ordering.
    case afterInvocation

    case afterModelCall

    var useReverseOrder: Bool {
        switch self {
        case .beforeInvocation: false
        case .beforeModelCall: false
        case .beforeTools: false
        case .beforeToolCall: false

        case .afterToolCall: true
        case .afterTools: true
        case .afterInvocation: true
        case .afterModelCall: true
        }
    }
}
