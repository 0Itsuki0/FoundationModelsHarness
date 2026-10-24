//
//  PluginRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

/// Registry for managing plugins.
/// One instance per session, aka: Agent. (Satisfied automatically when using with `SessionPropertyValues`)
class PluginRegistry {
    private(set) var plugins: [RegisteredPlugin] = []

    init(plugins: [RegisteredPlugin] = []) {
        self.plugins = plugins
    }

    /// Add to the registry and register hooks.
    /// If a plugin with the given name is already registered, return immediately
    func registerPlugin<T: Plugin>(_ plugin: T, to agent: Agent) async throws
        -> PluginName
    {
        guard !self.plugins.map(\.pluginName).contains(T.name) else {
            return T.name
        }

        let result = try await plugin.initAgent(agent)

        self.plugins.append(
            RegisteredPlugin(
                plugin: plugin,
                pluginName: T.name,
                hookIds: result.addedHooks,
                toolNames: result.addedTools
            )
        )

        return T.name
    }

    /// remove a plugin
    func removePlugin(_ name: String, from agent: Agent) async throws {
        guard let plugin = self.plugins.first(where: { $0.pluginName == name })
        else {
            return
        }

        plugin.hookIds.forEach(agent.removeHook(_:))
        plugin.toolNames.forEach(agent.removeTool(_:))
        self.plugins.removeAll(where: { $0.pluginName == name })

        // calling it after removing the hooks and tools as it is async and might take time.
        try await plugin.plugin.deInitAgent(agent)
    }
}

struct RegisteredPlugin {
    let plugin: any Plugin
    let pluginName: String
    let hookIds: [HookID]
    let toolNames: [String]
}
