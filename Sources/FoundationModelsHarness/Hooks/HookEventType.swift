//
//  HookEventType.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

/// Lifecycle events: Before/After pairs that bracket agent operations
/// - If a *before* event is called, the *after* event is guaranteed to be called.
/// - *after* events use reverse callback ordering for proper cleanup semantics.
public enum HookEventType: Sendable, Hashable, Equatable, CaseIterable {
    // MARK: - before events

    /// Triggered just before the model is invoked, aka: before messages are sent to the model for inference
    case beforeInvocation

    /// Triggered just before the model is invoked.
    case beforeModelCall

    /// Triggered before executing tools.
    case beforeTools

    /// Triggered just before a tool is executed, aka: before `Tool.call(arguments:)` is called.
    case beforeToolCall

    // MARK: After events
    /// Triggered after tool invocation completes. Uses reverse callback ordering.
    case afterToolCall

    /// Triggered after all tools complete execution. Uses reverse callback ordering.
    case afterTools

    /// Triggered after the model invocation completes. Uses reverse callback ordering.
    case afterModelCall

    /// Triggered at the end of an agent request. Uses reverse callback ordering.
    case afterInvocation

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
