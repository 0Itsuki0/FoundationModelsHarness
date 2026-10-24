//
//  PluginRegistry.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/18.
//

import FoundationModels

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

        let before = self.takeSnapshot(agent)
        try await plugin.initAgent(agent)
        let after = self.takeSnapshot(agent)

        self.plugins.append(
            RegisteredPlugin(
                plugin: plugin,
                pluginName: T.name,
                before: before,
                after: after
            )
        )

        return T.name
    }

    /// remove a plugin
    func removePlugin(_ name: String, from agent: Agent) async throws {
        guard !name.starts(with: reservedPackagePrefix) else {
            return
        }
        guard let plugin = self.plugins.first(where: { $0.pluginName == name })
        else {
            return
        }

        //        plugin.hookIds.forEach(agent.removeHook(_:))
        //        plugin.toolNames.forEach(agent.removeTool(_:))
        self.plugins.removeAll(where: { $0.pluginName == name })

        // calling it after removing the hooks and tools as it is async and might take time.
        try await plugin.plugin.deInitAgent(agent)
    }

    private func rollback(
        before: AgentConfigurationSnapshot,
        after: AgentConfigurationSnapshot
    ) {

    }

    private func hookDiff(
        before: [any HookEventHandler],
        after: [any HookEventHandler]
    ) -> (added: [HookID], removed: [HookID]) {

        return self.diff(
            before: before.map { $0.id },
            after: after.map { $0.id }
        )
    }

    //    private func toolDiff(

    private func takeSnapshot(_ agent: Agent) -> AgentConfigurationSnapshot {
        return AgentConfigurationSnapshot(
            hooks: agent.hookRegistry.registeredHooks,
            plugins: agent.pluginRegistry.plugins,
            tools: agent.tools,
            instruction: agent.instruction
        )
    }

    private func diff<T: Hashable>(
        before: [T],
        after: [T]
    ) -> (added: [T], removed: [T]) {

        let before = Set(before)
        let after = Set(after)

        let added = after.subtracting(before)
        let removed = before.subtracting(after)
        return (Array(added), Array(removed))
    }

}

struct RegisteredPlugin {
    let plugin: any Plugin
    let pluginName: String
    let before: AgentConfigurationSnapshot
    let after: AgentConfigurationSnapshot
}

struct AgentConfigurationSnapshot {
    let hooks: [any HookEventHandler]
    let plugins: [RegisteredPlugin]
    let tools: [ToolConfig]
    let instruction: Instructions
}
