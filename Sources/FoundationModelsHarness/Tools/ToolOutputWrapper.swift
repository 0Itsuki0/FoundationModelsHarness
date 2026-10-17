//
//  ToolOutputWrapper.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/17.
//

import FoundationModels

/// A generic Tool output for a cancelled tool call
public struct ToolOutputWrapper: ConvertibleToGeneratedContent, Sendable {
    static let schemaName = "ToolOutput"

    public var generatedContent: GeneratedContent {
        GeneratedContent(properties: [
            "status": status,
            "content": content.generatedContent,
        ])
    }

    @Generable
    public enum Status: Sendable {
        case success
        case error
    }

    public let status: Status
    public let content: JSONValue

    init(_ content: JSONValue, status: Status) {
        self.content = content
        self.status = status
    }

    init(_ error: Error) {
        self.content = .string(error.localizedDescription)
        self.status = .error
    }

    init(missingTool: String) {
        self.content = .string("Tool [\(missingTool)] does not exist.")
        self.status = .error
    }

    var segments: [Transcript.Segment] {
        return SegmentBuilder.segments(
            from: self.generatedContent,
            schemaName: Self.schemaName
        )
    }
}
