//
//  InvocableTool.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/11.
//

import FoundationModels

/// A type erased tool for programatic invocation.
public struct InvocableTool: Tool {
    public let name: String
    public let description: String
    public let parameters: GenerationSchema
    public let onToolCall: @Sendable (Arguments) async throws -> Output
    public let includesSchemaInInstructions: Bool = true  // default to true

    public typealias Arguments = GeneratedContent
    public typealias Output = GeneratedContent

    public init(
        name: String,
        description: String,
        schema: GenerationSchema,
        onToolCall: @escaping @Sendable (Arguments) async throws -> Output
    ) {
        self.name = name
        self.description = description
        self.parameters = schema
        self.onToolCall = onToolCall
    }

    public func call(arguments: Arguments) async throws -> Output {
        return try await self.onToolCall(arguments)
    }
}

extension InvocableTool {
    public init<T: Tool>(tool: T)
    where T.Output: ConvertibleToGeneratedContent {
        self.description = tool.description
        self.onToolCall = { argument in
            let output = try await tool.call(arguments: try argument.value())
            return GeneratedContent(output)
        }
        self.name = tool.name
        self.parameters = tool.parameters
    }

    public init<T: Tool>(tool: T) where T.Output: Generable {
        self.description = tool.description
        self.onToolCall = { argument in
            let output = try await tool.call(arguments: try argument.value())
            return GeneratedContent(output)
        }
        self.name = tool.name
        self.parameters = tool.parameters
    }
}
