#  (WIP) Foundation Models Harness

Dynamic profile: https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles

Brain storming:

- Tools
    - vendored tools: 
        - https://github.com/strands-agents/tools
        - https://github.com/strands-agents/harness-sdk/tree/main/harness-ts/src/tools
        - https://github.com/strands-agents/harness-sdk/blob/main/harness-ts/src/builtin-tools.ts
        - Docker / sandbox: https://strandsagents.com/docs/user-guide/sdk/sandbox/
    - Delegated tools: maybe a combination of [onToolOutput](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile/ontooloutput(perform:)) + throwing + history session property + [transcriptErrorHandlingPolicy](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/transcripterrorhandlingpolicy) to preserveTranscript
        ```swift
        // Get a reference to the session history.
        @SessionProperty(\.history) 
        var history

        var body: some LanguageModelSession.DynamicProfile {
            Profile {
                Instructions("You are a helpful assistant.")
                TodoWriteTool()
            }
            .onResponse { 
                // When the entries exceed `100`, perform a stateful update to the 
                // history so it only includes the last `50` entries.
                if history.count > 100 {
                    history = history.suffix(50)
                }
            }
        }
        ```
        - cannot use historyTransform here because it only performs a local transformation before prompting the model but doesn't affect the global state of the transcript.
    - additional states(see next point) available to tools
- State: agent state (key-value data that lives outside the conversation context and persists across requests) and invocation state (contextual data that lives for a single invocation)
    - Key: [SessionPropertyValues](https://developer.apple.com/documentation/foundationmodels/sessionpropertyvalues): When you need session-scoped properties beyond the built-in history, apply the SessionPropertyEntry() macro to a stored property in an extension on SessionPropertyValues. This makes the property accessible from the components within the session when you use LanguageModelSession.SessionProperty. For example, to create a custom Tool to access shared state, extend SessionPropertyValues with a new property and then access it with LanguageModelSession.SessionProperty from the tool (from https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles):
        
        ```swift
        extension SessionPropertyValues {
            @SessionPropertyEntry 
            var activatedSkills: [String: Bool] = [:]
        }

        struct PlannerTool: Tool {
            let description = "Update the state of the activated skills"
            
            // Read the shared session state for the currently activated skills.
            @SessionProperty(\.activatedSkills) 
            var activatedSkills


            @Generable
            struct Arguments {
                @Guide(description: "The skills to activate")
                var skills: [String]
            }


            func call(arguments: Arguments) -> String {
                // When the model calls this tool, update the skills to an active state.
                for skill in arguments.skills {
                    activatedSkills[skill] = true
                }
                return "Activated: \(arguments.skills.joined(separator: ", "))"
            }
        }

        ```

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
- plugin
- multi-agent:
    - a2a: https://strandsagents.com/docs/user-guide/sdk/multi-agent/agent-to-agent/
    - agent as tool: https://strandsagents.com/docs/user-guide/sdk/multi-agent/agents-as-tools/
    - swarm: https://strandsagents.com/docs/user-guide/sdk/multi-agent/swarm/
    - graph: https://strandsagents.com/docs/user-guide/sdk/multi-agent/graph/
    - workflow: https://strandsagents.com/docs/user-guide/sdk/multi-agent/workflow/
- context injection
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
- Hook
    - should just a be a wrapper around the life cycle modifiers: https://medium.com/@itsuki.enjoy/swift-hooks-for-foundation-models-a-little-cleaner-way-c822ed2cb25b
- Plugin
    - https://strandsagents.com/docs/user-guide/sdk/plugins/
    - key: [Create reusable components with a custom modifier](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles#Create-reusable-components-with-a-custom-modifier)


Strands: https://github.com/strands-agents/harness-sdk/tree/main/harness-ts

```ts
await createHarness({
  model: 'bedrock/global.anthropic.claude-opus-5', // "provider/name", a bare Bedrock id, or a Model instance
  effort: 'auto', // "auto" | "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max"
  instructions: undefined, // domain text appended to the system prompt
  tools: undefined, // your tools, added alongside the built-ins
  plugins: undefined, // your Strands plugins, added alongside the built-in ones
  mcpServers: undefined, // MCP servers: a mcpServers JSON path or the mapping itself
  builtinTools: undefined, // a list pins the set; a mapping edits the defaults (see below)
  backgroundTasks: undefined, // SDK Background Tasks policy; false to disable
  builtinPlugins: ['todos', 'environment'], // built-in feature plugins by name; [] for none
  caching: 'auto', // cache system prompt, tools & history where supported; null/false off
  contextManager: 'auto', // "auto" | "agentic" | a ContextManager instance | off (null/false)
  session: true, // true | { id?, dir? } | a SessionManager instance | off (null/false)
  skills: true, // true | dir(s)/URL(s) | an AgentSkills instance | off (null/false)
  memory: true, // true | { dir?, stores? } | a MemoryManager instance | off (null/false)
  interventions: undefined, // gate tool calls: 'ask' | 'smart' | a policy string | a .cedar file
  // ...any other AgentConfig field is passed straight through to Agent
})


```

