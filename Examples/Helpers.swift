//
//  Helpers.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import FoundationModelsHarness

struct GreetingTool: Tool {
    let name = "greet"
    let description = "greet a name."

    @Generable
    struct Arguments {
        @Guide(description: "The name to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        print("Tool[\(name)] called with arguments: \(arguments)")
        return "Hello \(arguments.name)"
    }
}

func printStream(_ stream: AsyncStream<AgentStreamEvent>)
    async
{
    for await snapshot in stream {
        print("snapshot: ", snapshot)
    }
    print()
}

func printHistory(_ history: Transcript.HistoryView) {
    print("---Session History---")

    for entry in history {
        switch entry {

        case .instructions(let value):
            print(value.description)

        case .prompt(let value):
            print(value.description)

        case .toolCalls(let value):
            print(value.description)

        case .toolOutput(let value):
            print(value.description)

        case .response(let value):
            print(value.description)

        case .reasoning(let value):
            print(value.description)

        case .data(let value):
            print(value.description)

        @unknown default:
            print("unknown entry")
        }
    }

    print("------")
}
