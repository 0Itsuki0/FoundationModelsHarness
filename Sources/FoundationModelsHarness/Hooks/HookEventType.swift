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
    /// Triggered after tool invocation completes. Uses reverse callback ordering
    case afterToolCall
    /// Triggered just before a tool is executed, aka: before `Tool.call(arguments:)` is called.
    case beforeToolCall

    /// Triggered just before the model is invoked, aka: before messages are sent to the model for inference
    case beforeInvocation
    
    case afterInvocation
    
    case beforeModelCall

    case afterModelCall

    var useReverseOrder: Bool {
        switch self {
        case .beforeInvocation: false
        case .beforeToolCall: false
        case .afterToolCall: true
        case .afterInvocation:
            true
        case .beforeModelCall:
            false
        case .afterModelCall:
            true
        }
    }
}
