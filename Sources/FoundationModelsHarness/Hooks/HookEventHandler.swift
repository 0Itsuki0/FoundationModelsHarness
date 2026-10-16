//
//  HookEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

public typealias HookID = UUID

public protocol HookEventHandler: Sendable, Identifiable where ID == HookID {
    static var eventType: HookEventType { get }
    static var useReverseOrder: Bool { get }

    associatedtype EventPayload: Sendable

    /// the error thrown will be propagated up directly to the `respond` or `streamResponse` after the *After* hooks being called.
    var callback: @Sendable (inout EventPayload) async throws -> Void { get }

    var options: HookCallbackOptions? { get }

    /// Callback ordering:
    /// By default, After event callbacks run in reverse registration order for cleanup symmetry.
    /// You can override this with explicit priority using the order option: lower values run first ,
    /// regardless of whether the hook uses reverse ordering or not.
    /// These are not enforced bounds: any numeric value works.
    /// Use values beyond them to run before or after the SDK’s hooks, or -Infinity/Infinity for guaranteed absolute ordering.
    /// e.g. `BuiltInHookOrder.sdkFirst` - 1 to always run before the SDK hooks
    var order: Int? { get }
}

extension HookEventHandler {
    public var order: Int? {
        return options?.order
    }

    public static var useReverseOrder: Bool {
        Self.eventType.useReverseOrder
    }
}
