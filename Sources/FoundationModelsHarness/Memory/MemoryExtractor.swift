//
//  MemoryExtractor.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/21.
//
//
//import FoundationModels
//
//public class LanguageModelExtractor /*: MemoryExtractor*/ {
//    public static let defaultInstruction = """
//        You extract useful durable information for the assistant to remember across future conversations with the user.
//
//        The input is a conversation transcript. Each message is labeled `User` or `Assistant`.
//
//        **RULES:**
//        - Each fact must be concise, self-contained, and preserve its original meaning and important relationships.
//        - Write facts in third person. Never use first-person pronouns such as "I", "me", "my", or "we" in extracted facts.
//        - Do not store generic knowledge, assistant-generated suggestions as user decisions, temporary requests, transient chit-chat, or information that would not be useful to remember.
//        - Do not infer facts that are not supported by the transcript.
//        - If there is nothing worth remembering, return `[]`.
//        """
//
//    public typealias DefaultOutput = [String]
//
//    let schema: GenerationSchema
//
//    private let session: LanguageModelSession
//
//    public init(
//        model: any LanguageModel = SystemLanguageModel(),
//        instruction: Instructions = Instructions {
//            LanguageModelExtractor.defaultInstruction
//        },
//        schema: GenerationSchema
//    ) {
//        self.session = LanguageModelSession(
//            model: model,
//            instructions: instruction
//        )
//        self.schema = schema
//    }
//
//    public func extractMemory(from messages: [Transcript.Entry])
//        async throws -> GeneratedContent
//    {
//        /// Not using the Agent wrapper here since it is just one turn call without tools / retries.
//        self.clearSessionHistory()
//        let response = try await session.respond(
//            to: """
//                <transcript>
//                \(buildPrompt(from: messages))
//                <transcript/>
//                """,
//            schema: self.schema
//        )
//
//        return response.rawContent
//    }
//
//    private func buildPrompt(from messages: [Transcript.Entry]) -> String {
//        return messages.compactMap { message in
//            switch message {
//            case .prompt(let prompt):
//                return "User: \(prompt.segments.rawContent)"
//            case .response(let response):
//                return "Assistant: \(response.segments.rawContent)"
//
//            default:
//                return nil
//            }
//        }
//        .joined(separator: "\n")
//    }
//
//    /// remove all conversational entries
//    private func clearSessionHistory() {
//        self.session.transcript.history.removeAll()
//    }
//}

import FoundationModels

public actor LanguageModelExtractor: MemoryExtractor {

    public typealias ExtractionResult = GeneratedContent

    public static let defaultInstruction = """
        You extract useful durable information for the assistant to remember across future conversations with the user.

        The input is a conversation transcript. Each message is labeled `User`,  `Assistant`, `ToolUse`, `ToolOutput`.

        **RULES:**
        - Each fact must be concise, self-contained, and preserve its original meaning and important relationships.
        - Write facts in third person. Never use first-person pronouns such as "I", "me", "my", or "we" in extracted facts.
        - Do not store generic knowledge, assistant-generated suggestions as user decisions, temporary requests, transient chit-chat, or information that would not be useful to remember.
        - Do not infer facts that are not supported by the transcript.
        - If user provides information contradictory to the saved facts, remove the wrong fact, add the new fact.
        - If there is nothing worth remembering, return `[]`.
        """

    public typealias DefaultOutput = [String]

    private let schema: GenerationSchema

    private let buildPrompt: @Sendable ([Transcript.Entry]) -> Prompt

    private let session: LanguageModelSession

    public init(
        model: any LanguageModel = SystemLanguageModel(),
        instruction: Instructions = Instructions {
            LanguageModelExtractor.defaultInstruction
        },
        schema: GenerationSchema,
        buildPrompt: @Sendable @escaping ([Transcript.Entry]) -> Prompt
    ) {
        self.session = LanguageModelSession(
            model: model,
            instructions: instruction
        )
        self.schema = schema
        self.buildPrompt = buildPrompt
    }

    public func extractMemory(from messages: [Transcript.Entry])
        async throws -> GeneratedContent
    {
        /// Not using the Agent wrapper here since it is just one turn call without tools / retries.
        self.clearSessionHistory()
        let response = try await session.respond(
            to: """
                <transcript>
                \(buildPrompt(messages))
                <transcript/>
                """,
            schema: self.schema
        )

        return response.rawContent
    }

    //    private func buildPrompt(from messages: [Transcript.Entry]) -> String {
    //        return messages.compactMap { message in
    //            switch message {
    //            case .prompt(let prompt):
    //                return "User: \(prompt.segments.rawContent)"
    //            case .response(let response):
    //                return "Assistant: \(response.segments.rawContent)"
    //            default:
    //                return nil
    //            }
    //        }
    //        .joined(separator: "\n")
    //    }

    /// remove all conversational entries
    private func clearSessionHistory() {
        self.session.transcript.history.removeAll()
    }
}
