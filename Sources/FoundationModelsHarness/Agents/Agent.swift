//
//  Agent.swift
//  FoundationModelsHarness
//
//  Created by Itsuki on 2026/10/10.
//

import FoundationModels
import SwiftUI

extension SessionPropertyValues {
    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    @SessionPropertyEntry
    public var agentState: StateStore = [:]

    /// Invocation state accessible to tools and application logic.
    /// Lives for a single invocation.
    /// State is not passed to the model during inference.
    @SessionPropertyEntry
    public var invocationState: StateStore = [:]

    @SessionPropertyEntry
    package var hookRegistry: HookRegistry = .init()
}

public typealias StateStore = [String: JSONValue]

struct AgentProfile: LanguageModelSession.DynamicProfile {
    let tools: [ToolConfig]
    let instruction: Instructions

    @SessionProperty(\.invocationState)
    var invocationState

    @SessionProperty(\.agentState)
    var agentState

    @SessionProperty(\.hookRegistry)
    var hookRegistry

    @SessionProperty(\.history)
    var history

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            instruction
            tools.map(\.tool)
        }
        // `transcriptErrorHandlingPolicy` needs to be set to `preserveTranscript`.
        // Otherwise, when we throw a FakeError, the previous request from the user will also be lost.
        .transcriptErrorHandlingPolicy(.preserveTranscript)
        .onToolOutput { toolCall, toolOutput in
            let handlers = hookRegistry.afterToolCallHandlers
            let event = AfterToolCallEventHandler.EventPayload(
                toolCall: toolCall,
                toolOutput: toolOutput,
                agent: createLocalAgent()
            )
            for handler in handlers {
                try await handler.callback(event)
            }
        }
        .onToolCall { toolCall in
            let handlers = hookRegistry.beforeToolCallHandlers
            let event = BeforeToolCallEventHandler.EventPayload(
                toolCall: toolCall,
                agent: createLocalAgent()
            )
            for handler in handlers {
                try await handler.callback(event)
            }
        }
    }

    private func createLocalAgent() -> LocalAgent {
        return LocalAgent(
            agentState: _agentState,
            invocationState: _invocationState,
            history: _history
        )
    }
}

extension Agent {
    public subscript<T>(dynamicMember keyPath: KeyPath<LanguageModelSession, T>)
        -> T
    {
        return self.session[keyPath: keyPath]
    }
}

@dynamicMemberLookup
@Observable
public final class Agent: Sendable {

    /// Agent state accessible to tools and application logic.
    /// Lives outside the conversation context and persists across requests
    var agentState: StateStore {
        get {
            session.properties.agentState
        }
        set {
            session.properties.agentState = newValue
        }
    }

    private let session: LanguageModelSession

    private var invocationState: StateStore {
        get {
            session.properties.invocationState
        }
        set {
            session.properties.invocationState = newValue
        }
    }

    private var hookRegistry: HookRegistry {
        get {
            session.properties.hookRegistry
        }
        set {
            session.properties.hookRegistry = newValue
        }
    }

    private let tools: [ToolConfig]
    private var delegatedToolName: [String] {
        self.tools.filter({ $0.delegate }).map(\.tool.name)
    }

    private func isDelegatedTool(_ toolName: String) -> Bool {
        self.delegatedToolName.contains(toolName)
    }

    public init(tools: [ToolConfig], instruction: Instructions) {
        let profile = AgentProfile(tools: tools, instruction: instruction)
        let session = LanguageModelSession(profile: profile)
        self.session = session
        self.tools = tools
        self.setupBuiltInHooks()
    }

    private func setupBuiltInHooks() {
        hookRegistry.afterToolCallHandlers.append(
            AfterToolCallEventHandler(
                callback: { [weak self] event in
                    guard let self else { return }
                    if isDelegatedTool(event.toolCall.toolName) {
                        throw DelegatedToolError(event.toolOutput)
                    }
                },
                options: .init(order: BuiltInHookOrder.sdkLast.rawValue)
            )
        )
    }

    // TODO: - add in wrappers for other respond / streamResponse methods

    @discardableResult
    public func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> AgentResult {

        do {
            let response = try await session.respond(to: prompt)
            return .modelOutput(
                rawContent: response.rawContent,
                usage: response.usage
            )
        } catch {
            if let error = error as? DelegatedToolError {
                addDelegatedToolOutput(error.toolOutput)
                return .delegatedToolOutput(error.toolOutput)
            }

            throw error
        }
    }

    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {

        return AsyncThrowingStream<AgentStreamEvent, Error> { continuation in
            Task { [session] in
                do {
                    for try await snapshot in session.streamResponse(to: prompt)
                    {
                        continuation.yield(
                            .contentUpdate(
                                rawContent: snapshot.rawContent,
                                usage: snapshot.usage
                            )
                        )
                    }
                    continuation.finish()
                    return

                } catch {
                    if let error = error as? DelegatedToolError {
                        addDelegatedToolOutput(error.toolOutput)
                        continuation.yield(
                            .delegatedToolOutput(error.toolOutput)
                        )
                        continuation.finish()
                        return
                    }

                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func addDelegatedToolOutput(
        _ output: Transcript.ToolOutput
    ) {
        // NOTE: Inserting a tool output is not necessary
        // aka: ToolCalls -> Response directly will not cause any error on the next generation using the transcript history,
        // but adding it here so that each tool call can be paired with an output
        session.transcript.history.append(
            .toolOutput(output)
        )
        session.transcript.history.append(
            .response(.init(segments: output.segments))
        )
    }
}

extension Array where Element == Transcript.Segment {
    var text: String {
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
