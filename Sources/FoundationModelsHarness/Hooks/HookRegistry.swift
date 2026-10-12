//
//  HookRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

struct HookRegistry {
    private var _afterToolCallHandlers: [AfterToolCallEventHandler]
    private(set) var afterToolCallHandlers: [AfterToolCallEventHandler] {
        get {
            return _afterToolCallHandlers.sortedByHookOrder
        }
        set {
            _afterToolCallHandlers = newValue
        }
    }

    private var _beforeToolCallHandlers: [BeforeToolCallEventHandler]
    private(set) var beforeToolCallHandlers: [BeforeToolCallEventHandler] {
        get {
            return _beforeToolCallHandlers.sortedByHookOrder
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

    @discardableResult
    mutating func addHook(_ hook: any HookEventHandler) -> HookID {
        if let hook = hook as? AfterToolCallEventHandler {
            self._afterToolCallHandlers.append(hook)
        }

        if let hook = hook as? BeforeToolCallEventHandler {
            self._beforeToolCallHandlers.append(hook)
        }

        return hook.id
    }

    mutating func removeHook(_ id: HookID) {
        self._afterToolCallHandlers.remove(id)
        self._beforeToolCallHandlers.remove(id)
    }

    mutating func removeHooks(for types: Set<HookEventType>) {
        for type in types {
            switch type {
            case .afterToolCall:
                self._afterToolCallHandlers.removeAll()
            case .beforeToolCall:
                self._beforeToolCallHandlers.removeAll()
            }
        }
    }

    mutating func removeAllHooks() {
        self = HookRegistry()
    }
}

extension Array where Element: Identifiable, Element.ID == UUID {
    mutating func remove(_ id: UUID) {
        self.removeAll(where: { $0.id == id })
    }
}

extension Array {
    /// useReverseOrder: For element with no explicit `order`, use registration order or reverse it.
    func sortedByHookOrder(
        order: (Element) -> Int?,
        useReverseOrder: Bool
    ) -> [Element] {
        self.sorted { first, second in
            let o1 = order(first)
            let o2 = order(second)

            // no explicit order. use registration order
            if o1 == nil, o2 == nil {
                return useReverseOrder ? true : false
            }

            // one of them has explicit order. respect it, ie: lower one first
            let defaultOrder = BuiltInHookOrder.default.rawValue
            return (o1 ?? defaultOrder) < (o2 ?? defaultOrder)
        }
    }
}
