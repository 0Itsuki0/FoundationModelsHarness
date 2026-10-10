//
//  HookEventType.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

/// https://strandsagents.com/docs/user-guide/sdk/agents/hooks-events/#available-events
public enum HookEventType: Sendable, Hashable, Equatable {
    /// Triggered after tool invocation completes. Uses reverse callback ordering
    case afterToolCall
    /// Triggered just before a tool is executed, aka: before `Tool.call(arguments:)` is called.
    case beforeToolCall

    var useReverseOrder: Bool {
        switch self {
        case .afterToolCall:
            true
        case .beforeToolCall: false
        }
    }
}
