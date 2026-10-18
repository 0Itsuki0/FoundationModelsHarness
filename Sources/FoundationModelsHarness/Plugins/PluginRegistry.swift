//
//  PluginRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

/// Registry for managing plugins.
class PluginRegistry {
    private var plugins: [RegisteredPlugin] = []

    init(plugins: [RegisteredPlugin] = []) {
        self.plugins = plugins
    }

    /// Add to the registry and register hooks.
    /// If a plugin with the given name is already registered, return immediately
    func registerPlugin<T: Plugin>(_ plugin: T, to agent: Agent) -> PluginName {
        guard !self.plugins.map(\.pluginName).contains(T.name) else {
            return T.name
        }
        /// add hooks
        let hookIds = plugin.hooks.map(agent.addHook(_:))

        /// add tools
        let toolNames = plugin.tools.map(agent.addTool(_:))

        self.plugins.append(
            RegisteredPlugin(
                plugin: plugin,
                pluginName: T.name,
                hookIds: hookIds,
                toolNames: toolNames
            )
        )
        return T.name
    }

    /// remove a plugin
    func removePlugin(_ name: String, from agent: Agent) {
        guard let plugin = self.plugins.first(where: { $0.pluginName == name })
        else {
            return
        }

        plugin.hookIds.forEach(agent.removeHook(_:))
        plugin.toolNames.forEach(agent.removeTool(_:))
        self.plugins.removeAll(where: { $0.pluginName == name })
    }
}

struct RegisteredPlugin {
    let plugin: any Plugin
    let pluginName: String
    let hookIds: [HookID]
    let toolNames: [String]
}
