//
//  HookRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

package struct HookRegistry {
    private var _afterToolCallHandlers: [AfterToolCallEventHandler]
    var afterToolCallHandlers: [AfterToolCallEventHandler] {
        get {
            return Self.orderHandlers(
                _afterToolCallHandlers,
                order: \.order,
                useReverseOrder: AfterToolCallEventHandler.useReverseOrder
            )
        }
        set {
            _afterToolCallHandlers = newValue
        }
    }

    private var _beforeToolCallHandlers: [BeforeToolCallEventHandler]
    var beforeToolCallHandlers: [BeforeToolCallEventHandler] {
        get {
            return Self.orderHandlers(
                _beforeToolCallHandlers,
                order: \.order,
                useReverseOrder: BeforeToolCallEventHandler.useReverseOrder
            )
        }
        set {
            _beforeToolCallHandlers = newValue
        }
    }

    init(
        afterToolCallHandlers: [AfterToolCallEventHandler],
        beforeToolCallHandlers: [BeforeToolCallEventHandler]
    ) {
        self._afterToolCallHandlers = afterToolCallHandlers
        self._beforeToolCallHandlers = beforeToolCallHandlers
    }

    init() {
        self._afterToolCallHandlers = []
        self._beforeToolCallHandlers = []
    }

    private static func orderHandlers<T>(
        _ handlers: [T],
        order: (T) -> Int,
        useReverseOrder: Bool
    ) -> [T] {
        handlers.sorted { first, second in
            let lowerFirst = order(first) < order(second)
            return useReverseOrder ? !lowerFirst : lowerFirst
        }
    }
}
