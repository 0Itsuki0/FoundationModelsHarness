//
//  Plugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import Foundation

public protocol Plugin {
    static var name: String { get }

    var hooks: [any HookEventHandler] { get }
    var tools: [ToolConfig] { get }
}

class PluginRegistry {
    private var plugins: [RegisteredPlugin] = []

    //    mutating func add

    func registerPlugin<T: Plugin>(_ plugin: T, to agent: Agent) {
//        agent.addHook()
    }

    //    func removePlugin(_ )
}

struct RegisteredPlugin {
    let plugin: any Plugin
    let hookIds: [HookID]
    let name: String
}

final class DelegationPlugin: Plugin {
    static let name: String = "D"

    var toolName: String?

    var hooks: [any HookEventHandler] {
        return [
            AfterToolCallEventHandler(
                callback: { event in
                    //                    setName()
                    self.toolName = ""
                },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            )
        ]
    }

    var tools: [ToolConfig] {
        []
    }

    //    = [
    //        AfterToolsEventHandler(callback: { event in
    //            self.toolName = ""
    //        }, options: .init(order: BuiltInHookOrder.sdkLast.rawValue))
    //    ]

    private func handleAfterTool(_ event: AfterToolsEventHandler.EventPayload)
        async
    {

    }
}
