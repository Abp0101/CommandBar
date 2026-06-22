# Limitations

CommandBar is an experimental local macOS agent. Its architecture demonstrates an agent loop, but its current tool coverage, verification and recovery mechanisms are deliberately limited.

## Tool coverage

The executor recognises a small set of actions, primarily application launching, Finder reveal operations and volume changes. Some planned capabilities described to the model do not yet have complete deterministic handlers. Natural-language steps that do not match a known handler may result in a limited AppleScript fallback or no observable action.

## Planning and parsing

Plans are JSON arrays of natural-language descriptions rather than validated, typed tool calls. Keyword matching can misinterpret a step, app-name extraction is basic, and malformed model output falls back to a generic step that may not be executable.

## Confirmation boundaries

Generated multi-step plans and saved workflows require confirmation. However, direct `open`, `launch` and `start` commands, plus eligible single-step app actions, currently bypass the plan screen. Confirmation should not be interpreted as universal coverage for every execution path.

## Verification and error handling

CommandBar generally waits for a handler to return but does not yet verify that the requested outcome occurred. AppleScript errors may be logged without being reflected in `ActionStep.Status`, and the interface can mark a sequence complete without end-to-end confirmation. There are no systematic retries, fallback policies or resumable recovery flows.

## Model behaviour

Intent and plan quality depend on the selected Ollama model and local configuration. The system prompt constrains requested output, but model responses can still be ambiguous, unsupported or malformed. No formal cross-model benchmark has yet been published.

## Security and privacy scope

Local Ollama inference keeps model requests on the configured local endpoint by default, but native actions still operate with the permissions granted to CommandBar and the current user account. The project has not undergone a formal security audit. Users should review plans and avoid granting unnecessary macOS permissions.

## Portability

The project targets macOS 14 or later and depends on macOS-specific frameworks and automation mechanisms. It is not designed as a cross-platform agent.

See the [evaluation plan](evaluation-plan.md) for proposed measurements and [agent design](agent-design.md) for planned improvements.
