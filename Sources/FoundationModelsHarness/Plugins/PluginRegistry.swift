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

        /// `after` will also contains the registered plugin itself but since it won't effect the rollback behavior, leaving it as it is..
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

        await self.rollback(
            before: plugin.before,
            after: plugin.after,
            on: agent
        )

        self.plugins.removeAll(where: { $0.pluginName == name })

        // calling it after removing the hooks and tools as it is async and might take time.
        try await plugin.plugin.deInitAgent(agent)
    }

    private func rollback(
        before: AgentSnapshot.ConfigurationSnapshot,
        after: AgentSnapshot.ConfigurationSnapshot,
        on agent: Agent
    ) async {
        self.rollbackHooks(before: before.hooks, after: after.hooks, on: agent)
        self.rollbackTools(before: before.tools, after: after.tools, on: agent)
        await self.rollbackPlugins(
            before: before._plugins,
            after: after._plugins,
            on: agent
        )
    }

    private func rollbackHooks(
        before: [any HookEventHandler],
        after: [any HookEventHandler],
        on agent: Agent
    ) {
        let (added, removed) = hookDiff(before: before, after: after)

        /// remove the added hooks
        added.map { $0.id }.forEach(agent.removeHook(_:))

        /// add back the removed hooks
        removed.forEach {
            agent.addHook($0)
        }
    }

    private func rollbackTools(
        before: [ToolConfig],
        after: [ToolConfig],
        on agent: Agent
    ) {
        let (added, removed) = toolDiff(before: before, after: after)

        /// remove the added tools
        added.map { $0.toolName }.forEach(agent.removeTool(_:))

        /// add back the removed tools
        removed.forEach {
            agent.addTool($0)
        }
    }

    /// Best effort rollback on the plugins.
    private func rollbackPlugins(
        before: [RegisteredPlugin],
        after: [RegisteredPlugin],
        on agent: Agent
    ) async {
        let (added, removed) = pluginDiff(before: before, after: after)

        let results = await withTaskGroup(of: (String, Error)?.self) {
            [added, removed, agent] group in

            var results: [(String, Error)?] = []

            /// remove the added plugins
            for plugin in added {
                let name = plugin.pluginName
                group.addTask { [name] in
                    do {
                        try await agent.removePlugin(name)
                        return nil
                    } catch {
                        return (name, error)
                    }

                }
            }

            /// add back the removed plugins
            for plugin in removed {
                let name = plugin.pluginName
                let plugin = plugin.plugin
                group.addTask { [plugin, name] in
                    do {
                        try await agent.addPlugin(plugin)
                        return nil
                    } catch {
                        return (name, error)
                    }
                }
            }

            for await result in group {
                results.append(result)
            }

            return results.compactMap { $0 }
        }

        if !results.isEmpty {
            print("Error rolling back plugins: ", results)
        }
    }

    /// Returning:
    /// added: hooks added by the plugin
    /// removed:  existing hooks removed by the plugin
    private func hookDiff(
        before: [any HookEventHandler],
        after: [any HookEventHandler]
    ) -> (added: [any HookEventHandler], removed: [any HookEventHandler]) {
        let diff = self.diff(
            before: before.map { $0.id },
            after: after.map { $0.id }
        )

        return (
            after.filter({ diff.added.contains($0.id) }),
            before.filter({ diff.removed.contains($0.id) })
        )
    }

    /// Returning:
    /// added: tools added by the plugin
    /// removed:  existing tools removed by the plugin
    private func toolDiff(
        before: [ToolConfig],
        after: [ToolConfig]
    ) -> (added: [ToolConfig], removed: [ToolConfig]) {
        let diff = self.diff(
            before: before.map { $0.toolName },
            after: after.map { $0.toolName }
        )
        return (
            after.filter({ diff.added.contains($0.toolName) }),
            before.filter({ diff.removed.contains($0.toolName) })
        )
    }

    /// Returning:
    /// added: other plugins added by a specific plugin during registration including the registered plugin itself
    /// removed:  existing other plugins removed by a specific plugin during registration
    private func pluginDiff(
        before: [RegisteredPlugin],
        after: [RegisteredPlugin]
    ) -> (added: [RegisteredPlugin], removed: [RegisteredPlugin]) {
        let diff = self.diff(
            before: before.map { $0.pluginName },
            after: after.map { $0.pluginName }
        )
        return (
            after.filter({ diff.added.contains($0.pluginName) }),
            before.filter({ diff.removed.contains($0.pluginName) })
        )
    }

    private func takeSnapshot(_ agent: Agent)
        -> AgentSnapshot.ConfigurationSnapshot
    {
        return agent.takeSnapshot().configuration
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
    let before: AgentSnapshot.ConfigurationSnapshot
    let after: AgentSnapshot.ConfigurationSnapshot
}
