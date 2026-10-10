//
//  ToolDelegation.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels

struct DelegatedToolError: Error {
    let toolOutput: Transcript.ToolOutput

    init(_ toolOutput: Transcript.ToolOutput) {
        self.toolOutput = toolOutput
    }
}
