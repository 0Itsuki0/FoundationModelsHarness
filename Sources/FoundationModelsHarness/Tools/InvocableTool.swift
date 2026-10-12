//
//  InvocableTool.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/11.
//

import Foundation
import FoundationModels

/// A type erased tool for programatic invocation.
public struct InvocableTool: Tool {
    public let name: String
    public let description: String
    public let parameters: GenerationSchema
    public let onToolCall: @Sendable (Arguments) async throws -> Output
    public let includesSchemaInInstructions: Bool = true  // default to true

    public typealias Arguments = GeneratedContent

    /// A wrapper around `PromptRepresentable`
    public struct Output: PromptRepresentable {
        let output: PromptRepresentable

        init(_ output: PromptRepresentable) {
            self.output = output
        }

        public var promptRepresentation: Prompt {
            self.output.promptRepresentation
        }
    }

    public func call(arguments: Arguments) async throws -> Output {
        return try await self.onToolCall(arguments)
    }
}

/// T.Output: PromptRepresentable
/// Inherited By: `ConvertibleToGeneratedContent`, `Generable`
/// Conforming Types: `Attachment`(Conforms when Content conforms to `Copyable` and `Escapable`), `GeneratedContent`, `ImageReference`, `Prompt`
///
/// `Generable` inherits `ConvertibleToGeneratedContent`
/// `GeneratedContent` conforms `ConvertibleToGeneratedContent`
/// `ImageReference` conforms `ConvertibleToGeneratedContent`
extension InvocableTool {
    public init(
        name: String,
        description: String,
        schema: GenerationSchema,
        onToolCall:
            @escaping @Sendable (Arguments) async throws -> Output
    ) {
        self.name = name
        self.description = description
        self.parameters = schema
        self.onToolCall = onToolCall
    }

    public init<T: Tool>(
        tool: T
    ) {
        self.description = tool.description
        self.onToolCall = { argument in
            let output = try await tool.call(
                arguments: try argument.value()
            )
            return Output(output)
        }
        self.name = tool.name
        self.parameters = tool.parameters
    }
}
