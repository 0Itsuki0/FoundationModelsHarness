//
//  SegmentBuilder.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/13.
//

import FoundationModels

enum SegmentBuilder {
    /// Create segments from `PromptRepresentable`.
    ///
    /// `PromptRepresentable`:
    /// Inheritance: `ConvertibleToGeneratedContent`, `Generable`
    /// conformance type: `ImageReference`, `Attachment`, `GeneratedContent`, `Prompt`
    static func segments(from prompt: PromptRepresentable) async -> [Transcript
        .Segment]
    {
        /// ConvertibleToGeneratedContent, Generable, ImageReference, Attachment, GeneratedContent
        /// all conforms to InstructionsRepresentable and will be handled here.
        if let instructions = prompt as? InstructionsRepresentable {
            return segments(from: instructions)
        }

        let profile = LanguageModelSession.Profile {}.onPrompt {
            throw PromptReceived(prompt: $0)
        }

        let session = LanguageModelSession(profile: profile)
        /// make sure the prompt is preserved even when there is an error calling the model
        session.transcriptErrorHandlingPolicy = .preserveTranscript
        let prompt = prompt.promptRepresentation
        do {
            let _ = try await session.respond(to: prompt)
        } catch {
            if let error = error as? PromptReceived {
                return error.prompt.segments
            }
        }
        /// fallback if the PromptReceived is never caught
        return session.transcript.history.compactMap { $0.asPrompt }.first?
            .segments ?? []
    }

    /// Create segments from `GeneratedContent`.
    ///
    /// The handling here mirrors how the system transforms it.
    static func segments(
        from generatedContent: GeneratedContent,
        schemaName: String
    ) -> [Transcript.Segment] {
        switch generatedContent.kind {
        case .null:
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]
        case .bool(let value):
            return [.text(.init(content: String(value)))]
        case .number(let value):
            return [.text(.init(content: String(value)))]
        case .string(let value):
            return [.text(.init(content: value))]
        case .array(let value):
            return value.flatMap {
                segments(from: $0, schemaName: schemaName)
            }
        case .structure(_, _):
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]
        @unknown default:
            return [
                .structure(
                    .init(
                        schemaName: schemaName,
                        content: generatedContent
                    )
                )
            ]

        }
    }

    /// Create segments from `InstructionsRepresentable`.
    static func segments(from instructions: InstructionsRepresentable)
        -> [Transcript.Segment]
    {
        let session = LanguageModelSession(
            instructions: instructions.instructionsRepresentation
        )
        return session.transcript.compactMap { $0.asInstruction }.first?
            .segments ?? []
    }

    /// Create segments from `JSONValue`.
    /// `schemaName` default to `GeneratedContent`, what the system use for values created directly with `GeneratedContent.init`
    static func segments(
        from jsonValue: JSONValue,
        schemaName: String
    )
        -> [Transcript.Segment]
    {
        return self.segments(
            from: jsonValue.generatedContent,
            schemaName: schemaName
        )
    }

}

private struct PromptReceived: Error {
    let prompt: Transcript.Prompt
}
