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
    var hookRegistry: HookRegistry = .init()

    @SessionPropertyEntry
    var isInternalRetry: Bool = false
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

    private var isInternalRetry: Bool {
        get {
            session.properties.isInternalRetry
        }
        set {
            session.properties.isInternalRetry = newValue
        }
    }

    private let tools: [ToolConfig]
    private var delegatedToolName: [String] {
        self.tools.filter({ $0.delegate }).map(\.invocableTool.name)
    }

    private func isDelegatedTool(_ toolName: String) -> Bool {
        self.delegatedToolName.contains(toolName)
    }

    private let profile: AgentProfile

    public init(tools: [ToolConfig], instruction: Instructions) {
        let instruction = ToolConfig.injectDelegationPrompt(
            for: tools,
            on: instruction
        )
        let profile = AgentProfile(tools: tools, instruction: instruction)
        self.profile = profile
        let session = LanguageModelSession(profile: profile)
        self.session = session
        self.tools = tools
        self.setupBuiltInHooks()
    }

    private func setupBuiltInHooks() {
        // TODO: - maybe changed this to use `endTurn` instead so that `AfterInvocation` hooks can be triggered
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

    @discardableResult
    public func addHook(_ hook: any HookEventHandler) -> HookID {
        return self.hookRegistry.addHook(hook)
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
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) async throws -> AgentResult {
        self.isInternalRetry = false

        defer {
            self.resetInvocationState()
        }

        let beforeCallUsage = session.usage

        do {
            let response = try await session.respond(
                to: prompt,
                metadata: metadata
            )
            let entry: Transcript.Response =
                self.session.lastResponse
                ?? .init(segments: [.text(.init(content: response.content))])
            return AgentResult(
                stopReason: .endTurn,
                lastMessage: entry,
                invocationState: invocationState,
                usage: calculateTurnUsage(
                    before: beforeCallUsage,
                    after: session.usage
                )
            )
        } catch {
            let usage = calculateTurnUsage(
                before: beforeCallUsage,
                after: session.usage
            )

            if let error = error.delegatedError {
                let response = addDelegatedToolOutput(error.toolOutput)
                return AgentResult(
                    stopReason: .endTurn,
                    lastMessage: response,
                    invocationState: invocationState,
                    usage: usage
                )
            }

            if let error = error.responseFinishError {
                /// history already contains the response. returning it directly.
                return AgentResult(
                    stopReason: .endTurn,
                    lastMessage: error.response,
                    invocationState: invocationState,
                    usage: usage
                )
            }

            if let error = error.retryError {
                return try await retry(
                    for: error,
                    options: options,
                    metadata: metadata
                )
            }

            throw error
        }
    }

    private func retry(
        for error: RetryModelGenerationError,
        options: GenerationOptions,
        metadata: [String: any ConvertibleToGeneratedContent],
    ) async throws -> AgentResult {
        self.isInternalRetry = true
        defer {
            self.isInternalRetry = false
        }

        // A dummy empty prompt in order to force the retry from the current history
        // the dummy will be removed from the history within `AgentProfile.onPrompt`
        return try await self.respond(
            to: "",
            options: buildRetryGenerationOptions(options, for: error),
            metadata: buildRetryMetadata(metadata)
        )
    }

    private func calculateTurnUsage(
        before: LanguageModelSession.Usage,
        after: LanguageModelSession.Usage
    ) -> LanguageModelSession.Usage {
        return LanguageModelSession.Usage(
            input: .init(
                totalTokenCount: after.input.totalTokenCount
                    - before.input.totalTokenCount,
                cachedTokenCount: after.input.cachedTokenCount
                    - before.input.cachedTokenCount
            ),
            output: .init(
                totalTokenCount: after.output.totalTokenCount
                    - before.output.totalTokenCount,
                reasoningTokenCount: after.output.reasoningTokenCount
                    - before.output.reasoningTokenCount
            )
        )
    }

    /// Update tool calling mode based on the error to avoid infinite looping
    private func buildRetryGenerationOptions(
        _ options: GenerationOptions,
        for error: RetryModelGenerationError
    ) -> GenerationOptions {
        var options = options
        switch error {
        case .afterToolOutput:
            /// Make sure the `toolCallingMode` is not `required` to avoid an infinite tool-calling loop (which is one of the FoundationModels SDK bug as of 2026.10.12)
            if options.toolCallingMode == .required {
                options.toolCallingMode = .allowed
            }
        }
        return options
    }

    private func buildRetryMetadata(
        _ metadata: [String: any ConvertibleToGeneratedContent]
    ) -> [String: any ConvertibleToGeneratedContent] {
        var metadata = metadata
        metadata[InternalMetadataKey.dummyPrompt] = true
        return metadata
    }

    public func streamResponse(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent] = [:]
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        return AsyncThrowingStream<AgentStreamEvent, Error> { continuation in
            // Required to convert ConvertibleToGeneratedContent to GeneratedContent to avoid the following concurrency error:
            // Passing closure as a 'sending' parameter risks causing data races between code in the current isolation context and concurrent execution of the closure
            let metadata = metadata.mapValues(\.generatedContent)

            Task { [session, resetInvocationState, metadata] in
                await streamHelper(
                    prompt: prompt,
                    metadata: metadata,
                    session: session,
                    resetInvocationState: resetInvocationState,
                    beforeCallUsage: session.usage,
                    streamingInto: continuation,
                )
            }
        }
    }

    private func retryStream(
        for error: RetryModelGenerationError,
        options: GenerationOptions,
        metadata: [String: any ConvertibleToGeneratedContent],
        session: LanguageModelSession,
        resetInvocationState: () -> Void,
        beforeCallUsage: LanguageModelSession.Usage,
        streamingInto continuation: AsyncThrowingStream<AgentStreamEvent, Error>
            .Continuation
    ) async {
        self.isInternalRetry = true
        defer {
            self.isInternalRetry = false
        }

        let metadata = buildRetryMetadata(metadata)

        // A dummy empty prompt in order to force the retry from the current history
        // the dummy will be removed from the history within `AgentProfile.onPrompt`
        await self.streamHelper(
            prompt: "",
            options: buildRetryGenerationOptions(options, for: error),
            metadata: buildRetryMetadata(metadata),
            session: session,
            resetInvocationState: resetInvocationState,
            beforeCallUsage: session.usage,
            streamingInto: continuation
        )
    }

    private func streamHelper(
        prompt: String,
        options: GenerationOptions = GenerationOptions(),
        metadata: [String: any ConvertibleToGeneratedContent],
        session: LanguageModelSession,
        resetInvocationState: () -> Void,
        beforeCallUsage: LanguageModelSession.Usage,
        streamingInto continuation: AsyncThrowingStream<AgentStreamEvent, Error>
            .Continuation
    ) async {
        defer {
            resetInvocationState()
        }

        do {
            for try await snapshot in session.streamResponse(
                to: prompt,
                metadata: metadata
            ) {
                /// the `calculateTurnUsage` is essentially the same as `snapshot.usage`in this case
                continuation.yield(
                    .init(
                        rawContent: snapshot.rawContent,
                        usage: calculateTurnUsage(
                            before: beforeCallUsage,
                            after: session.usage
                        )
                    )
                )
            }
            continuation.finish()
            return

        } catch {
            let usage = calculateTurnUsage(
                before: beforeCallUsage,
                after: session.usage
            )
            if let error = error.delegatedError {
                addDelegatedToolOutput(error.toolOutput)
                continuation.yield(
                    .init(
                        segments: error.toolOutput.segments,
                        usage: usage
                    )
                )
                continuation.finish()
                return
            }

            if let error = error.responseFinishError {
                /// `history` already contains the response. Don't need to add anything.
                continuation.yield(
                    .init(
                        segments: error.response.segments,
                        usage: usage
                    )
                )
                continuation.finish()
                return
            }

            if let error = error.retryError {
                await retryStream(
                    for: error,
                    options: options,
                    metadata: metadata,
                    session: session,
                    resetInvocationState: resetInvocationState,
                    beforeCallUsage: session.usage,
                    streamingInto: continuation
                )
                continuation.finish()
                return
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
        if !session.transcript.history.contains(where: { $0.id == output.id }) {
            session.transcript.history.append(
                .toolOutput(output)
            )
        }
        let response = Transcript.Response(segments: output.segments)
        session.transcript.history.append(
            .response(response)
        )
        return response
    }
}

extension Transcript.Entry {
    var asToolOutput: Transcript.ToolOutput? {
        if case .toolOutput(let output) = self {
            return output
        }
        return nil
    }

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

    var asPrompt: Transcript.Prompt? {
        if case .prompt(let value) = self {
            return value
        }
        return nil
    }

    var asInstruction: Transcript.Instructions? {
        if case .instructions(let value) = self {
            return value
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

extension Error {
    var isRetryError: Bool {
        return self.isError(RetryModelGenerationError.self)
    }

    var retryError: RetryModelGenerationError? {
        return self.error(RetryModelGenerationError.self)
    }

    var delegatedError: DelegatedToolError? {
        return self.error(DelegatedToolError.self)
    }

    var responseFinishError: ResponseFinishedError? {
        return self.error(ResponseFinishedError.self)
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
