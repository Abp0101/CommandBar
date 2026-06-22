# CommandBar architecture

CommandBar is a native macOS command interface built with Swift, SwiftUI and AppKit. It uses a locally hosted Ollama model for language tasks and keeps execution authority in a bounded Swift tool layer.

## System flow

```text
Global hotkey
    → CommandBarView receives a natural-language command
    → Workflow match or intent classification
        → Question
            → Add optional frontmost-app and selected-text context
            → Stream an answer from Ollama
            → Render the answer inline
        → Action
            → Generate a short ordered plan with Ollama
            → Convert descriptions into ActionStep values
            → Present multi-step plan for confirmation
            → Dispatch confirmed steps through ActionExecutor
            → Update the execution state shown by the interface
            → Complete, cancel or return to idle
```

Saved workflows enter the same plan-and-confirm path. Direct `open`, `launch` and `start` commands use a deterministic fast path, and eligible single-step app actions may execute without showing a confirmation plan.

## Components

| Component | Responsibility |
|---|---|
| `CommandBarView` | Owns the interaction state, routes submissions and renders answers, plans and execution progress. |
| `AIService` | Calls Ollama's local chat endpoint for fallback intent classification, plan generation and streamed answers. |
| `ActionExecutor` | Maps step descriptions to bounded native handlers using `NSWorkspace`, `NSAppleScript` and selected system processes. |
| `WorkflowStore` | Persists named, reusable step sequences as JSON in Application Support. |
| `ContextCapture` | Supplies optional selected text and frontmost-app context for answers. |
| `HistoryStore` and `SuggestionEngine` | Support command history and keyboard-oriented suggestions. |
| `HotkeyManager` and `CommandBarWindowController` | Register the global shortcut and manage the floating macOS panel. |

## Local model boundary

By default, `AIService` sends requests to `http://localhost:11434/api/chat` and uses the locally configured Ollama model. The model proposes classifications, answers and plan descriptions; it does not receive direct access to macOS APIs. `ActionExecutor` remains the execution boundary.

Intent classification uses deterministic action prefixes first, then asks the model for an `action` or `question` decision. Plan generation requests a JSON array of short, ordered descriptions restricted by the system prompt to supported capabilities.

## State control

`BarState` defines five UI states:

- `idle`: ready for input
- `thinking`: classifying or planning
- `answering`: receiving or displaying streamed text
- `planning`: displaying proposed `ActionStep` values
- `executing`: displaying the current step and overall progress

The explicit state model keeps question answering, plan review and execution visually distinct. `ActionStep.Status` also defines pending, running, done and failed states, although execution errors are not yet fully propagated into those statuses.

## Execution boundary

The executor currently supports a narrow set of handlers:

- application launch and activation through `NSWorkspace`
- Finder reveal operations
- volume changes through fixed AppleScript commands
- limited AppleScript fallbacks for recognised patterns
- system process use for local application lookup

This is a constrained handler layer rather than an unrestricted autonomous shell. Broader tool schemas, result reporting and verification are planned work.
