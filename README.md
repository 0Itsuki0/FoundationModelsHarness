# (WIP) Foundation Models Harness

## Overview

Foundation Models Harness is a Swift package for building and running AI agents on top of Apple's [Foundation Models](https://developer.apple.com/documentation/foundationmodels) framework, inspired by [Strands Agents](https://github.com/strands-agents/harness-sdk). It wraps a `LanguageModelSession` in an `Agent` that owns the agent loop: model calls, tool execution, and the lifecycle around them.

On top of the plain session, we get:

- **[Hooks](#hooks)** to intercept agent life cycles to, for example, monitoring agent execution and tool usage, modifying tool calls, retrying tool calls and model calls.
- **[Plugins](#plugins)** to bundle hooks and tools into reusable behaviors.
- **[Tool delegation](#tool-delegation)** to return a tool's output directly to the user as the final answer.
- **State** shared between the agent, hooks, and tools, without sending anything to the model:
    - `agentState` persists across requests
    - `invocationState` lives for a single invocation.

Requires iOS / macOS / visionOS / watchOS 27.2+ and Swift 6.4+.

### Installation

Add the package with Swift Package Manager. In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/0Itsuki0/FoundationModelsHarness`. Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/0Itsuki0/FoundationModelsHarness", branch: "main"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["FoundationModelsHarness"]
    ),
]
```

### Quick Start

```swift
import FoundationModels
import FoundationModelsHarness

let agent = await Agent(
    model: SystemLanguageModel(),
    tools: [.init(tool: GreetingTool())],
    instruction: .init("You are a helpful assistant.")
)

// Single response
let result = await agent.respond(to: "greet itsuki")
print(result)

// Streaming
for await event in agent.streamResponse(to: "greet dan") {
    print(event)
}
```

`respond` and `streamResponse` never throw. The outcome, including errors, comes back on the `AgentResult`. Per-call parameters (`schema`, `options`, `metadata`, `contextOptions`, `invocationState`, `toolExecutionMode`) fall back to `Agent.defaultInvocationOptions` when `nil`.

Tool calls the model emits in a single turn run in parallel by default. Pass `toolExecutionMode: .sequential` to run them one at a time.

See [`Examples/`](Examples/) for runnable examples.


## Hooks

Hooks let you add logging, validation, guardrails, or custom logic at any point in the agent loop. Lifecycle events come in Before/After pairs that bracket agent operations: if a *before* event fires, its *after* event is guaranteed to fire.

### Lifecycle

![Hook lifecycle](docs/hook-lifecycle.svg)

| Event | When | What a callback can do |
|-------|------|------------------------|
| `BeforeInvocation` | Start of an agent request, before the prompt is added to the history | Mutate `prompt`; set `cancel` to end the invocation with that content as the response |
| `BeforeModelCall` | Just before the model is invoked | Set `cancel` to skip the model call with that content as the response |
| `BeforeTools` | Before executing the tool calls of a turn | Set `cancel` to cancel all tool calls with that content as their output |
| `BeforeToolCall` | Just before a single tool is executed | Mutate `toolCall` (name / arguments); set `cancel` to cancel the call with that content as its output |
| `AfterToolCall` | After a single tool completes | Mutate `toolResult`; set `retry` to run the tool again (`attemptCount` available) |
| `AfterTools` | After all tool calls of a turn complete | Set `endTurn` to end the loop with that content as the final response |
| `AfterModelCall` | After the model call completes | Mutate `stopReason` (`endTurn` / `toolUse` / `refusal`); set `retry` to call the model again (`attemptCount` available) |
| `AfterInvocation` | End of an agent request | Read `result`; set `retry` to rerun the invocation, or `resume` with a new prompt |

Every event payload also carries an `agent` snapshot to read the `history` and read or write `agentState` / `invocationState`.

```swift
let id = agent.addHook(
    AfterModelCallEventHandler(callback: { event in
        // retry once on refusal
        if case .refusal = event.stopReason, event.attemptCount < 2 {
            event.retry = true
        }
    })
)

agent.removeHook(id)
agent.removeHooks(for: [.afterModelCall])
agent.removeAllHooks()
```

### Ordering

Before callbacks run in registration order. After callbacks run in reverse registration order for cleanup symmetry. Override this with an explicit `order` in `HookCallbackOptions`: lower values run first. `BuiltInHookOrder` provides reference points, with `sdkFirst` / `sdkLast` marking where the SDK's own hooks run.

```swift
agent.addHook(
    BeforeToolCallEventHandler(
        callback: { event in event.cancel = "failed to greet. Do it yourself." },
        // cancellation is last-wins, so run it after the SDK's hooks
        options: .init(order: BuiltInHookOrder.sdkLast.rawValue + 1)
    )
)
```

Mutations such as `cancel`, `retry`, and `endTurn` are last-wins across callbacks.

See [`Examples/Hooks/`](Examples/Hooks/) for an example per event.


## Plugins

Plugins change the typical behavior of an agent. They let you introduce concepts like skills, steering, or other behavioral modifications into the agent loop by composing the low-level primitives the `Agent` exposes: hooks and tools.

Implement the `Plugin` protocol:

```swift
struct LoggingPlugin: Plugin {
    static let name: PluginName = "LoggingPlugin"

    var tools: [ToolConfig] = []

    var hooks: [any HookEventHandler] {
        [
            BeforeModelCallEventHandler(callback: { event in
                print("model call: \(event.agent.history.count) entries")
            }),
            AfterToolCallEventHandler(callback: { event in
                print("tool result: \(event.toolResult)")
            }),
        ]
    }
}

agent.addPlugin(LoggingPlugin())
agent.removePlugin(LoggingPlugin.name)
```

Adding a plugin registers its hooks and tools on the agent. Removing it unregisters exactly those hooks and tools. A plugin whose `name` is already registered is ignored.


## Long-Term Memory

Long-term memory lets an agent remember facts about the user across conversations. Modeled after the [Strands memory manager](https://strandsagents.com/docs/user-guide/sdk/memory/overview/), it is a plugin built from hooks and tools, added by creating the agent with an `AgentMemoryConfiguration`:

```swift
let agent = await Agent(
    instruction: .init("You are a helpful assistant."),
    memoryConfiguration: config
)
```

A configuration has four parts:

| Property | Description |
|----------|-------------|
| `store` | The `MemoryStore` that persists memories and answers searches. |
| `autoExtraction` | Extracts memories from the conversation in the background. Omit it to disable extraction. |
| `searchMemoryToolConfig` | Adds a `search_user_info` tool so the model can look up memories. |
| `addMemoryToolConfig` | Adds an `add_llm_memory` tool so the model can save memories itself. We recommend disabling it and using `autoExtraction` instead. |

Each tool's `ToolOption` can override the tool's `name` and `description`. 

### Auto Extraction

The model decides when to call a tool, so it often forgets to save something worth remembering. Auto extraction removes that decision from the model.

After each invocation, the plugin buffers the latest turn. Once `turnBufferCount` turns (5 by default) are buffered, it hands them to the `extractor` in the background, without delaying the response, and passes the outcome to `onExtraction`. Turns still buffered when the plugin is removed are extracted then.

The extractor receives the user prompts, the assistant responses, and the calls to and outputs of the search tool. The search results let it see which stored facts the user has just contradicted, so it can remove them as well as add new ones.

`LanguageModelExtractor` is the built-in extractor. It runs a separate `LanguageModelSession` that reads the turns and returns `GeneratedContent` matching `DefaultExtractionResult`:

- `add`: new facts (`MemoryEntryPartial`) to save.
- `remove`: ids of stored facts that are no longer true.

Override its `model`, `instruction`, `schema`, or `buildPrompt` to change what is extracted, or implement the `MemoryExtractor` protocol for your own extractor. The extraction result is not written to the store for you: write it in `onExtraction`, in whatever shape your store accepts.

```swift
let config = AgentMemoryConfiguration(
    store: store,
    autoExtraction: .init(
        extractor: LanguageModelExtractor(),
        turnBufferCount: 2,
        onExtraction: { result in
            guard let content = try? result.get(),
                let extraction = try? content.value(
                    LanguageModelExtractor.DefaultExtractionResult.self
                )
            else { return }
            try? await store.addMemories(extraction.add)
            try? await store.deleteMemories(extraction.remove.map(Int64.init))
        }
    ),
    addMemoryToolConfig: .init(enabled: false),
    searchMemoryToolConfig: .init(enabled: true)
)
```

### Memory Stores

A `MemoryStore` implements `addMemory` and `searchMemory`. Their input types are `Generable` and their result types are `PromptRepresentable`, so each store defines the argument schema and output of the memory tools.

The package provides three stores. Each one deduplicates on add, removes memories unused for `maxUnusedDays` (30 by default), and updates a memory's last-used date when a search returns it.

| Store | Storage | Matching |
|-------|---------|----------|
| `InMemoryMemoryStore` | Memory, for testing and debugging | Cosine similarity of `NaturalLanguage` sentence embeddings, plus normalized-text match |
| `FileMemoryStore` | A JSON file | Same as `InMemoryMemoryStore` |
| `SQLiteMemoryStore` (`SQLiteStore` target) | An SQLite database, through [GRDB](https://github.com/groue/GRDB.swift) | FTS5 full-text search |

Tune each store with `MemoryStoreConfiguration`:

| Property | Description |
|----------|-------------|
| `searchConfiguration` | `similarityThreshold` and `topK` filter search results. With `useSameCategoryFallback`, a search that matches nothing returns every memory in the requested categories. |
| `addThresholdSimilarity` | A new memory is skipped if an existing one is at least this similar. `nil` always adds. |
| `removeThresholdSimilarity` | Embedding stores only. Existing memories less similar to a new one than this (nearly opposite) are removed. `nil` never removes. |
| `maxUnusedDays` | Days before an unused memory is removed. `nil` keeps memories forever. |
| `eraseDatabaseOnSchemaChange` | `SQLiteMemoryStore` only. Recreates the database when the schema changes. Destroys data, so use it only during development. |

Similarity means different things per store. The embedding stores use cosine similarity, from -1 to 1. `SQLiteMemoryStore` uses an FTS5 score relative to the query's score against itself, from 0 to 1: it measures shared words, so it can't detect opposite facts.

See [`Examples/AgentMemory.swift`](Examples/AgentMemory.swift) for a complete example.


## Tool Delegation

By default, a tool's output is sent back to the model to generate a final response. A delegated tool short-circuits that: its output is returned directly to the user as the final answer.

```swift
let agent = await Agent(
    tools: [.init(tool: GreetingTool(), delegate: true)],
    instruction: .init("You are a helpful assistant.")
)

let result = await agent.respond(to: "greet itsuki and dan")
```

When a tool is configured with `delegate: true`, the harness ensures:

1. The agent loop exits immediately after a successful delegation (via `endTurn`).
2. The delegated tool's output becomes the final assistant message, and is added to the history so follow-up prompts see it.
3. The delegated tool is the only tool called in the turn. Any other tool call in the same turn is cancelled.

If the delegated tool throws, the error is penetrated directly to the `AgentResult`, same as regular tool throwing.


----


## WIP-ing

- vended tools
    - https://github.com/strands-agents/tools
    - https://github.com/strands-agents/harness-sdk/tree/main/harness-ts/src/tools
    - https://github.com/strands-agents/harness-sdk/blob/main/harness-ts/src/builtin-tools.ts
    - Docker / sandbox: https://strandsagents.com/docs/user-guide/sdk/sandbox/
- MCP
- memory
    - https://strandsagents.com/docs/user-guide/sdk/memory/overview/
- Conversation Manager
    - https://strandsagents.com/docs/user-guide/sdk/agents/state/#conversation-manager
    - maybe by using [historyTransform(_:)](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile/historytransform(_:)): Applies a transformation to the history prior to invoking the model.
- context management / context manager
    - https://strandsagents.com/docs/user-guide/sdk/context-management/
- session manager: single agent session is automatic with LanguageModelSession. what needs to be considered is multi-agent case.
    - Orchestrator state and configuration
    - Individual agent states and result within the orchestrator
    - Cross-agent shared state and context
    - Execution flow and node transition history
- multi-agent:
    - a2a: https://strandsagents.com/docs/user-guide/sdk/multi-agent/agent-to-agent/
    - agent as tool: https://strandsagents.com/docs/user-guide/sdk/multi-agent/agents-as-tools/. https://github.com/0Itsuki0/SwiftFoundationModels_AgentAsTool/blob/main/AgentAsTool.swift
    - swarm: https://strandsagents.com/docs/user-guide/sdk/multi-agent/swarm/
    - graph: https://strandsagents.com/docs/user-guide/sdk/multi-agent/graph/
    - workflow: https://strandsagents.com/docs/user-guide/sdk/multi-agent/workflow/
- Retry Strategies
    - https://strandsagents.com/docs/user-guide/sdk/agents/retry-strategies/
- fallback:
    - for example, a fall back model
        ```ts
        const router = new ModelRouter([
          new RoutingCandidate({ model: primary, name: 'primary' }),
          new RoutingCandidate({ model: fallback, name: 'fallback' }),
        ])
        const agent = new Agent({ model: router })
        ```
    - https://strandsagents.com/docs/api/typescript/FallbackStrategy/
