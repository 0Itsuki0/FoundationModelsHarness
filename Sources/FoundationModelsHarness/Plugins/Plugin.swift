//
//  Plugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import Foundation

public typealias PluginName = String

/// Plugin: Interface for objects that extend agent functionality.
///
/// Specifically, Plugins provide a composable way to add behavior changes to agents by registering hook callbacks in their `initAgent` method.
/// Each plugin must have a unique name for identification and duplicate prevention.
/// One Plugin type can only be attached to an Agent once.
///
/// Implement this protocol to create your own plugins.
public protocol Plugin {

    /// A stable string identifier for the plugin.
    static var name: PluginName { get }

    /// Initialize the plugin with the agent instance.
    /// Implement this method to register hooks, tools, and perform custom initialization.
    ///
    /// This maybe called for multiple times on multiple different agent instances.
    ///
    /// Returning
    /// - `PluginInitResult` for clean up purpose.
    func initAgent(_ agent: Agent) async throws -> PluginInitResult

    /// DeInitialize the plugin with the agent instance.
    /// Use this function for clean up.
    /// Changes on instructions, other plugins, hooks and tools added will be recovered automatically.
    func deInitAgent(_ agent: Agent) async throws
}

public struct PluginInitResult: Sendable {
    let addedHooks: [HookID]
    let addedTools: [ToolName]
}
