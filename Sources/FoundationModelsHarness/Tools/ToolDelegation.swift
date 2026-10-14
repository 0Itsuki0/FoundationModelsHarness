//
//  ToolDelegation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

/// Internal *fake* error only used for custom model invocation / tool use / response handling
protocol FakeError: Error, Sendable {}

struct DelegatedToolError: FakeError {
    let toolOutput: Transcript.ToolOutput

    init(_ toolOutput: Transcript.ToolOutput) {
        self.toolOutput = toolOutput
    }
}
