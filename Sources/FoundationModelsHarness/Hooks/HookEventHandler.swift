//
//  HookEventHandler.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

public protocol HookEventHandler: Sendable {
    static var eventType: HookEventType { get }
    static var useReverseOrder: Bool { get }

    associatedtype EventPayload: Sendable

    var options: HookCallbackOptions? { get }

    var order: Int { get }
}

extension HookEventHandler {
    public var order: Int {
        return options?.order ?? BuiltInHookOrder.default.rawValue
    }

    public static var useReverseOrder: Bool {
        Self.eventType.useReverseOrder
    }
}
