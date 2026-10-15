//
//  HookRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

@propertyWrapper
struct HookOrdered<T: HookEventHandler> {
    private var handlers: [T] = []

    init(_ handlers: [T]) {
        self.wrappedValue = handlers
    }

    init(wrappedValue: [T]) {
        self.wrappedValue = wrappedValue
    }

    var wrappedValue: [T] {
        get {
            return handlers.sortedByHookOrder(
                order: \.order,
                useReverseOrder: T.useReverseOrder
            )
        }
        set { handlers = newValue }
    }
}

struct HookRegistry {
    // MARK: - Before Event
    @HookOrdered
    private(set) var beforeInvocationHandlers: [BeforeInvocationEventHandler]

    @HookOrdered
    private(set) var beforeToolCallHandlers: [BeforeToolCallEventHandler]

    // MARK: - After Event
    @HookOrdered
    private(set) var afterToolCallHandlers: [AfterToolCallEventHandler]
    
//    @HookOrdered
//    private(set) var afterModelCallHandlers: [AfterToolCallEventHandler]
//
//    
//    @HookOrdered
//    private(set) var afterInvocationHandlers: [AfterToolCallEventHandler]


    init(
        beforeInvocationHandlers: [BeforeInvocationEventHandler] = [],
        beforeToolCallHandlers: [BeforeToolCallEventHandler] = [],
        afterToolCallHandlers: [AfterToolCallEventHandler] = [],
    ) {
        self.beforeInvocationHandlers = beforeInvocationHandlers
        self.beforeToolCallHandlers = beforeToolCallHandlers
        self.afterToolCallHandlers = afterToolCallHandlers
    }

    @discardableResult
    mutating func addHook(_ hook: any HookEventHandler) -> HookID {
        if let hook = hook as? BeforeInvocationEventHandler {
            self.beforeInvocationHandlers.append(hook)
        }

        if let hook = hook as? BeforeToolCallEventHandler {
            self.beforeToolCallHandlers.append(hook)
        }

        if let hook = hook as? AfterToolCallEventHandler {
            self.afterToolCallHandlers.append(hook)
        }

        return hook.id
    }

    mutating func removeHook(_ id: HookID) {
        self.beforeInvocationHandlers.remove(id)
        self.beforeToolCallHandlers.remove(id)
        self.afterToolCallHandlers.remove(id)
    }

    mutating func removeHooks(for types: Set<HookEventType>) {
        for type in types {
            switch type {
            case .beforeInvocation:
                self.beforeInvocationHandlers.removeAll()
            case .beforeToolCall:
                self.beforeToolCallHandlers.removeAll()
            case .afterToolCall:
                self.afterToolCallHandlers.removeAll()
                
            default:
                break
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
