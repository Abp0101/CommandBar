# Agent design

## Design goal

CommandBar explores how a local language model can participate in a useful macOS action loop while deterministic application code retains control over execution. The design separates language interpretation from native tool access and makes multi-step plans visible before they run.

## Core capabilities

- **Intent classification:** distinguishes questions from requested macOS actions using deterministic prefixes with an Ollama fallback.
- **Multi-step planning:** asks the local model for a short JSON action plan and represents each item as an `ActionStep`.
- **Human confirmation:** presents generated multi-step plans and saved workflows before execution, with an explicit Run or Cancel choice.
- **Native tool execution:** dispatches supported steps through `NSWorkspace`, `NSAppleScript` and selected local system processes.
- **Persistent workflows:** saves reusable action sequences as local JSON and matches them by trigger phrase.
- **State-machine control:** models idle, thinking, answering, planning and executing as explicit UI states.
- **Local LLM inference through Ollama:** performs classification, planning and streamed question answering through a configurable local Ollama endpoint.

## Agent loop

1. Accept a command from the global macOS overlay.
2. Check for a saved workflow or classify the command as a question or action.
3. Stream questions to the interface, or generate steps for actions.
4. Show multi-step plans and wait for human confirmation.
5. Execute supported steps sequentially through the native tool layer.
6. Update visible progress, then dismiss or return to an inactive state.

The current implementation also has fast paths for simple app-launch commands and eligible single-step app actions. These paths favour low latency but do not use the multi-step confirmation screen.

## Safety model

CommandBar does not immediately execute generated multi-step or destructive action plans. Multi-step actions are presented as a plan before confirmation, and the user can cancel at that point. The executor exposes a limited set of native handlers rather than giving the model direct access to macOS APIs, and an explicit guard prevents the AppleScript fallback from emptying Trash.

These controls reduce risk but are not a complete security boundary. Plan descriptions are natural language, handler matching is keyword-based, and most actions do not yet verify their outcome. CommandBar should therefore be treated as an experimental local agent whose proposed actions still require user judgement.

## Current limitations

- Limited predefined handlers cover only a subset of possible macOS actions.
- There is no full post-action verification yet.
- There is no formal benchmark suite yet.
- Recovery from failed actions is limited.
- Execution failures are logged in some paths but are not consistently surfaced in the UI.
- Plan generation uses natural-language step descriptions rather than typed tool calls.

## Planned improvements

- **Structured tool schemas:** replace description matching with typed tool names and validated arguments.
- **Post-action verification:** check observable outcomes before marking a step complete.
- **Retries and fallbacks:** define bounded retry policies and safe alternative handlers.
- **Benchmark suite:** measure classification, planning, execution and safety behaviour against a versioned task set.
- **Execution trace logging:** record inputs, proposed tool calls, confirmation decisions, results and timing locally for debugging and evaluation.
