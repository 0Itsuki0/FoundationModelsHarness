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
    public var agentState: AgentState = [:]

    /// Invocation state accessible to tools and application logic.
    /// Lives for a single invocation.
    /// State is not passed to the model during inference.
    @SessionPropertyEntry
    public var invocationState: InvocationState = [:]

    @SessionPropertyEntry
    package var hookRegistry: HookRegistry = .init()
}

public typealias InvocationState = [String: JSONValue]
public typealias AgentState = [String: JSONValue]

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
    var agentState: AgentState {
        get {
            session.properties.agentState
        }
        set {
            session.properties.agentState = newValue
        }
    }

    private let session: LanguageModelSession

    private var invocationState: InvocationState {
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
        self.addHook(
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

    public func addHook(_ hook: any HookEventHandler) {
        self.hookRegistry.addHook(hook)
    }

    public func removeHook(_ id: HookID) {
        self.hookRegistry.removeHook(id)
    }

    public func removeHooks(for types: Set<HookEventType>) {
        self.hookRegistry.removeHooks(for: types)
    }

    public func removeAllHooks() {
        self.hookRegistry.removeAllHooks()
    }

    private func resetInvocationState() {
        self.invocationState = .init()
    }

    // TODO: - add in wrappers for other respond / streamResponse methods

    @discardableResult
    public func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) async throws -> AgentResult {
        self.invocationState.clearRetry()

        defer {
            self.resetInvocationState()
        }

        do {
            let response = try await session.respond(to: prompt)
            let entry: Transcript.Response =
                self.session.lastResponse
                ?? .init(segments: [.text(.init(content: response.content))])
            return AgentResult(
                stopReason: .modelOutput,
                lastMessage: entry,
                invocationState: invocationState
            )
        } catch {
            if let error = error.delegatedError {
                let response = addDelegatedToolOutput(error.toolOutput)
                return AgentResult(
                    stopReason: .delegatedToolOutput,
                    lastMessage: response,
                    invocationState: invocationState
                )
            }

            if error.isRetryError {
                return try await retry(options: options)
            }

            throw error
        }
    }

    private func retry(options: GenerationOptions) async throws -> AgentResult {
        print(#function)
        invocationState.setRetry()
        defer {
            invocationState.clearRetry()
        }
        return try await self.respond(to: "", options: options)
    }

    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions()
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {

        return AsyncThrowingStream<AgentStreamEvent, Error> { continuation in

            Task { [session, resetInvocationState] in
                await streamHelper(
                    prompt: prompt,
                    session: session,
                    resetInvocationState: resetInvocationState,
                    streamingInto: continuation
                )
            }
        }
    }

    private func retryStream(
        options: GenerationOptions,
        session: LanguageModelSession,
        resetInvocationState: () -> Void,
        streamingInto continuation: AsyncThrowingStream<AgentStreamEvent, Error>
            .Continuation
    ) async {
        print(#function)
        invocationState.setRetry()
        defer {
            invocationState.clearRetry()
        }
        await self.streamHelper(
            prompt: "",
            options: options,
            session: session,
            resetInvocationState: resetInvocationState,
            streamingInto: continuation
        )
    }

    private func streamHelper(
        prompt: String,
        options: GenerationOptions = GenerationOptions(),
        session: LanguageModelSession,
        resetInvocationState: () -> Void,
        streamingInto continuation: AsyncThrowingStream<AgentStreamEvent, Error>
            .Continuation
    ) async {
        defer {
            resetInvocationState()
        }

        do {
            for try await snapshot in session.streamResponse(to: prompt) {
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
            if let error = error.delegatedError {
                addDelegatedToolOutput(error.toolOutput)
                continuation.yield(
                    .delegatedToolOutput(error.toolOutput)
                )
                continuation.finish()
                return
            }

            if error.isRetryError {
                await retryStream(
                    options: options,
                    session: session,
                    resetInvocationState: resetInvocationState,
                    streamingInto: continuation
                )
            }

            continuation.finish(throwing: error)
        }

    }

    @discardableResult
    private func addDelegatedToolOutput(
        _ output: Transcript.ToolOutput
    ) -> Transcript.Response {
        // NOTE: Inserting a tool output is not necessary
        // aka: ToolCalls -> Response directly will not cause any error on the next generation using the transcript history,
        // but adding it here so that each tool call can be paired with an output
        session.transcript.history.append(
            .toolOutput(output)
        )
        let response = Transcript.Response(segments: output.segments)
        session.transcript.history.append(
            .response(response)
        )
        return response
    }
}

extension Transcript.Entry {
    var asResponse: Transcript.Response? {
        if case .response(let response) = self {
            return response
        }
        return nil
    }

    var asToolCalls: Transcript.ToolCalls? {
        if case .toolCalls(let calls) = self {
            return calls
        }
        return nil
    }
}

extension LanguageModelSession {
    var lastResponse: Transcript.Response? {
        self.transcript.history.compactMap {
            $0.asResponse
        }.last
    }
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

extension Error {
    var isRetryError: Bool {
        return self.isError(RetryError.self)
    }

    var delegatedError: DelegatedToolError? {
        return self.error(DelegatedToolError.self)
    }

    func isError<T: Error>(_ type: T.Type) -> Bool {
        return self.error(type) != nil
    }

    func error<T: Error>(_ type: T.Type) -> T? {
        if let error = self as? T {
            return error
        }

        if let error = self as? LanguageModelSession.ToolCallError {
            return error.underlyingError.error(type)
        }
        return nil
    }
}
