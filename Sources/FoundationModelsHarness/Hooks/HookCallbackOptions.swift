//
//  HookCallbackOptions.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import Foundation

public struct HookCallbackOptions: Sendable, Hashable, Equatable {
    /// Callback ordering:
    /// By default, After event callbacks run in reverse registration order for cleanup symmetry.
    /// You can override this with explicit priority using the order option: lower values run first.
    /// These are not enforced bounds: any numeric value works.
    /// Use values beyond them (e.g. `BuiltInHookOrder.sdkFirst` - 1) to run before or after the SDK’s hooks, or -Infinity/Infinity for guaranteed absolute ordering.
    public let order: Int?
}

/// Presets for hook execution order. Lower values run first.
/// Any number is a valid order — these presets are not bounds, just convenient
/// reference points.
/// `sdkFirst`/`sdkLast` mark where the SDK's own hooks run,
/// so you can position yours relative to them.
public enum BuiltInHookOrder: Int, Hashable, Sendable {
    case sdkFirst = -100
    case interventionOutput = -90
    case `default` = 0
    case `modelRouting` = 50
    case interventionInput = 90
    case sdkLast = 100
}
