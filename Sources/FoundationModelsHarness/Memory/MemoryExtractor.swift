//
//  MemoryExtractor.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/21.
//

import FoundationModels

public actor LanguageModelExtractor: MemoryExtractor {

    public typealias ExtractionResult = GeneratedContent

    private let schema: GenerationSchema

    private let buildPrompt: @Sendable ([Transcript.Entry]) -> Prompt

    private let session: LanguageModelSession

    public init(
        model: any LanguageModel = SystemLanguageModel(),
        instruction: Instructions = Instructions {
            LanguageModelExtractor.defaultInstruction
        },
        schema: GenerationSchema = DefaultExtractionResult.self
            .generationSchema,
        buildPrompt: @Sendable @escaping ([Transcript.Entry]) -> Prompt =
            LanguageModelExtractor.buildPrompt
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

    /// remove all conversational entries
    private func clearSessionHistory() {
        self.session.transcript.history.removeAll()
    }
}

extension LanguageModelExtractor {
    public static let defaultInstruction = """
        You extract useful durable information for the assistant to remember across future conversations with the user.

        The input is a conversation transcript. Each message is labeled `User`,  `Assistant`, `ToolUse`, `ToolOutput`.

        **RULES:**
        - The `User` is the **Single source of Truth**.
        - Each fact must be concise, self-contained, and preserve its original meaning and important relationships.
        - Write facts in third person. Never use first-person pronouns such as "I", "me", "my", or "we" in extracted facts.
        - Do not store generic knowledge, assistant-generated suggestions as user decisions, temporary requests, transient chit-chat, or information that would not be useful to remember.
        - Do not infer facts that are not supported by the transcript.
        - If user provides information different from the saved facts, **remove** the wrong fact, **add** the new fact.
        """

    /// Default build prompt function
    @Sendable public static func buildPrompt(from messages: [Transcript.Entry])
        -> Prompt
    {
        let string: String = messages.compactMap { message in
            switch message {
            case .prompt(let prompt):
                return "User: \(prompt.segments.rawContent)"
            case .response(let response):
                return "Assistant: \(response.segments.rawContent)"
            case .toolCalls(let calls):
                let getMemoryTools = calls.filter({
                    $0.toolName == MemoryToolDefault.searchToolName
                })
                guard !getMemoryTools.isEmpty else {
                    return nil
                }
                // rename the tool so that it matches the prompt
                return
                    "ToolUse (\(MemoryToolDefault.searchToolName)): \(getMemoryTools.map(\.arguments)) "

            case .toolOutput(let output):
                guard output.toolName == MemoryToolDefault.searchToolName else {
                    return nil
                }
                return "ToolOutput: \(output.segments.rawContent)"
            default:
                return nil
            }
        }
        .joined(separator: "\n")

        return Prompt { string }
    }

    @Generable()
    public struct DefaultExtractionResult {
        @Guide(description: "Facts to save to assistant's memory.")
        public let add: [MemoryEntryPartial]

        @Guide(
            description:
                "Ids of the wrong facts that needs to be removed from assistant's memory."
        )
        public let remove: [Int]
    }
}
