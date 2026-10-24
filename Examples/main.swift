//
//  main.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/08.
//

import Accelerate
import FoundationModels
import FoundationModelsHarness
import GRDB
import NaturalLanguage
import SQLiteStore

private let testEntries: [MemoryEntryPartial] = {
    let facts: [(MemoryCategory, String)] = [
        /// About the user
        (
            .preferences,
            "The user prefers concise answers without lengthy explanations."
        ),
        (
            .preferences,
            "The user's favorite pokemon is pikachu."
        ),
        (
            .tasks,
            "The user wants to build an on-device agent harness on top of Apple Foundation Models."
        ),
        (
            .preferences,
            "Never commit or push to git without the user's explicit permission."
        ),
        (.preferences, "Do not add third-party dependencies to the project."),
        (
            .preferences,
            "The user said to only do exactly what is asked and not change unrelated code."
        ),

        /// About the work
        (
            .project,
            "FoundationModelsHarness is a Swift package providing agents, tools, memory and goal plugins for Foundation Models."
        ),
        (
            .project,
            "Long-term memory uses NLEmbedding sentence embeddings with cosine distance for similarity search."
        ),
        (
            .preferences,
            "Types use UpperCamelCase and functions use lowerCamelCase following Swift API design guidelines."
        ),
        (
            .preferences,
            "NLEmbedding was chosen over NLContextualEmbedding because the task is semantic similarity."
        ),
        /// About the world
        (.people, "Ken owns the backend API that the iOS app talks to."),
        (
            .people,
            "Foundation Models documentation: https://developer.apple.com/documentation/foundationmodels"
        ),
        /// About time
        (
            .tasks,
            "On 2026-10-08 the user started the FoundationModelsHarness project."
        ),
        (
            .tasks,
            "On 2026-10-19 a tool delegation bug was fixed when a delegated tool is added or removed."
        ),
        (
            .tasks,
            "Add automatic clean up of memories that have not been used for 30 days."
        ),
    ]
    return facts.map {
        .init(
            category: $0.0,
            fact: $0.1,
        )
    }
}()

struct AddMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    var name = "add_llm_memory"
    var description = """
        Save information to **Assistant's** long-term memory for recall in future conversations.
        - Save multi-word, concise, self-contained fact that preserves its original meaning and important relationships. NEVER Sentence.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(
        call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil
    ) {
        self.call = call

        if let nameOverride { self.name = nameOverride }
        if let descriptionOverride { self.description = descriptionOverride }
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
    }
}

struct SearchMemoryTool<
    Arguments: Generable,
    Output: PromptRepresentable
>: Tool {
    var name = "search_user_info"
    var description = """
        Look up user-related information such as preferences, rules, relationships.
        - Search with multi-word query. NEVER Sentence.
        """

    let includesSchemaInInstructions: Bool = true

    private let call: @Sendable (Self.Arguments) async throws -> Self.Output

    init(
        call: @escaping @Sendable (Self.Arguments) async throws -> Self.Output,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil
    ) {
        self.call = call

        if let nameOverride { self.name = nameOverride }
        if let descriptionOverride { self.description = descriptionOverride }
    }

    func call(arguments: Arguments) async throws -> Output {
        return try await self.call(arguments)
    }
}

private let testingQuery: [String] = [
    /// paraphrases of stored facts (expected: close match)
    "What is my name?",
    "Where does the user live and what timezone are they in?",
    "Does the user like short or long responses?",
    "Which programming language does the user use?",
    "Am I allowed to push commits to git?",
    "Can I add an external library to the package?",
    "How does memory search work?",
    "Why NLEmbedding instead of NLContextualEmbedding?",
    "How do I run the example?",
    "Is NLEmbedding thread safe?",
    "Who is responsible for the backend?",
    "Where are the Foundation Models docs?",
    "How large is the on-device model's context window?",
    "When did the project start?",
    "What bug was fixed recently?",
    "What are the open tasks?",

    /// opposites of stored facts (expected: large distance)
    "Feel free to commit and push to git anytime.",
    "I really like pikachu! Super important!",

    /// unrelated (expected: no match)
    "What's the weather like in Paris today?",
    "Recommend a good pasta recipe.",
]

let url = URL.temporaryDirectory.appending(path: "memory.json")
try? FileManager.default.removeItem(at: url)
let store = try SQLiteMemoryStore(url: url)
let _ = try await store.addMemories(testEntries)

//let results = try await store.searchMemory(
//    .init(categories: [.identity], query: "user's name")
//)
//let store = InMemoryMemoryStore()

//print(results)
//try await Task.sleep(for: .milliseconds(300))
//print(try await store.allMemories().filter({ $0.category == .identity }))

//print(calculateCosineDistance(v1, b: v2))

//let store = InMemoryMemoryStore(memories: testEntries)
//let store = try FileMemoryStore(fileURL: url, existingMemories: harnessTestEntries)

let addTool = AddMemoryTool(call: { argument in
    return try await store.addMemory(argument)
})
let searchTool = SearchMemoryTool(call: { argument in
    return try await store.searchMemory(argument)
})

//do {
//    let session = LanguageModelSession(
//        model: SystemLanguageModel(),
//        tools: [
//            addTool,
//            searchTool,
//        ],
//        instructions: Instructions {
//            """
//            Search for information about the user (\(searchTool.name)) when your answer depends on their
//            preferences, decisions, or circumstances.
//            Save (\(addTool.name)) lasting facts about the user as short self-contained statements.
//            """
//        }
//    )
//    for query in testingQuery {
//        let _ = try await session.respond(to: query)
//        printHistory(session.transcript.history)
//        session.transcript.history.removeAll()
//    }
//} catch {
//    print(error)
//}

//
//let agent = await Agent(
//    tools: [
////        .init(tool: GreetingTool(), delegate: true)
//    ],
//    instruction: .init("You are a helpful assistant.")
//)
//agent.addTool(.init(tool: GreetingTool(), delegate: true))

//agent.addHook(
//    AfterToolCallEventHandler(callback: { event in
//        if event.attemptCount < 2 {
//            event.retry = true
//        } else {
//            event.toolResult = .failure(NSError(domain: "failed", code: 1))
//        }
//    })
//)

//agent.agentState["app"] = "Test"
//let result = await agent.respond(
//    to: "hello. greet itsuki",
//    invocationState: ["resume": true]
//)

//print("result", result)
////print("response: ", response.rawContent as Any)
//print("-----")
//await agent.respond(to: "how's going")

// testing stream
//await printStream(agent.streamResponse(to: "hello. greet itsuki.", invocationState: ["resume": true]))
//await printStream(
//    agent.streamResponse(to: "how's going?")
//)
//
//printHistory(agent.history)

//await toolDelegation()

@Generable()
struct ExtractionResult {
    @Guide(description: "Facts to save to assistant's memory.")
    let add: [MemoryEntryPartial]

    @Guide(
        description:
            "Ids of the wrong facts that needs to be removed from assistant's memory."
    )
    let remove: [Int]
}

extension Array where Element == Transcript.Segment {
    var rawContent: String {
        return self.compactMap { segment -> String? in
            switch segment {
            case .text(let text):
                text.content.isEmpty ? nil : text.content
            case .structure(let structure):
                structure.content.jsonString
            case .attachment(_):
                nil
            @unknown default:
                nil
            }
        }.joined(separator: "\n")
    }

}

let extractor = LanguageModelExtractor(
    schema: ExtractionResult.generationSchema,
    buildPrompt: { entries in
        let string: String = entries.compactMap { message in
            switch message {
            case .prompt(let prompt):
                return "User: \(prompt.segments.rawContent)"
            case .response(let response):
                return "Assistant: \(response.segments.rawContent)"
            case .toolCalls(let calls):
                let getMemoryTools = calls.filter({
                    $0.toolName == searchTool.name
                })
                guard !getMemoryTools.isEmpty else {
                    return nil
                }
                return
                    "Tool Use (Get Memory): \(getMemoryTools.map(\.arguments)) "

            case .toolOutput(let output):
                guard output.toolName == searchTool.name else {
                    return nil
                }
                return "Tool Result: \(output.segments.rawContent)"
            default:
                return nil
            }
        }
        .joined(separator: "\n")

        return Prompt(string)
    }
)

do {
    let session = LanguageModelSession(
        model: SystemLanguageModel(),
        tools: [
//                        addTool,
            searchTool
        ],
        instructions: Instructions {
            """
            User's prompt that you need to respond to is surrounded by the `<user>` tag.
            Additional instructions that you need to follow is surrounded by the `<system>` tag.

            Look up information about the user using the [\(searchTool.name)] tool **whenever** knowing their preferences, works, tasks, or relationships *COULD possibly* make you better assistant them. 
            - Use the tool **proactively**. Do NOT wait for the user to prompt you explicitly to use it.  
            - Only use it as a reference. It is not guaranteed to be correct. It can be out-of-date. Never question what the user says.
            - Always answer in natural tone. 
            - If there is no results, answer normally. 
            - Never inform the user about the search result.
            """
        }
    )
    
//    try await store.addMemories([.init(category: .identity, fact: "tfact", embeddings: nil)])
    //    let _ = try await session.respond(
//        to: """
//                <user>Hey! my favorite pokemon is Pikachu</user> 
//                <system>Use the [\(searchTool.name)] tool to look up user-related information **proactively**.</system>
//            """
//    )

//    let _ = try await session.respond(
//        to: """
//                <user>Let's talk more about my favorite pokemon!</user> 
//                <system>Use the [\(searchTool.name)] tool to look up user-related information **proactively**.</system>
//            """
//    )

    //    let _ = try await session.respond(
    //        to: """
    //                <user>why no look up what it is before you give shit?</user>
    //                <system>[\(searchTool.name)] tool available for user-related information look up. Use the tool **proactively**.</system>
    //            """
    //    )
    //    let _ = try await session.respond(to: "We have just talked about it. Why are you not looking it up. You don't even remember what it is? I am asking you why you are not searching fuck shit. YOu have the fucking tool on what it is. answer my question. why you are not looking it up.")
    //    let _ = try await session.respond(to: "You have the fucking tool to know my preference instead of asking what it is fuck you shit. why are you not using the \(searchTool.name) tool. Try it you dick. what tools do you have access to. print it out fuck.")

//    printHistory(session.transcript.history)
    //    let content = try await extractor.extractMemory(
    //        from: Array(session.transcript.history)
    //    )
    //    print(content)

} catch {
    print(error)
}

//extension Transcript.Entry {
//    static func user(_ message: String) -> Transcript.Entry {
//        return .prompt(
//            Transcript.Prompt(segments: [.text(.init(content: message))])
//        )
//    }
//
//    static func assistant(_ message: String) -> Transcript.Entry {
//        return .response(
//            Transcript.Response(segments: [.text(.init(content: message))])
//        )
//    }
//}
//
//for scenario in scenarios {
//    let transcript: [Transcript.Entry] = scenario.flatMap({ user, assistant in
//        [.user(user), .assistant(assistant)]
//    })
//    do {
//        let content = try await extractor.extractMemory(from: transcript)
//        print(content)
//    } catch {
//        print(error)
//    }
//}


await agentMemory()
