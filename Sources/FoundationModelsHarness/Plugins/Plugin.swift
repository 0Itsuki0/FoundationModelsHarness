//
//  Plugin.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import Foundation

public typealias PluginId = UUID

public protocol Plugin: Sendable, Identifiable where ID == PluginId {
    static var name: String { get }

    var hooks: [any HookEventHandler] { get }
    var tools: [ToolConfig] { get }
}
