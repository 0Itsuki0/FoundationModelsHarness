//
//  Plugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import Foundation

public typealias PluginName = String

/// Plugins change the typical behavior of an agent.
/// They let you introduce concepts like Skills, steering, or other behavioral modifications into the agent loop by composing on the low-level primitives the Agent class exposes such as tools and hooks.
/// Implement this protocol to create your own plugins.
public protocol Plugin {
    static var name: PluginName { get }

    var hooks: [any HookEventHandler] { get }
    var tools: [ToolConfig] { get }
}
