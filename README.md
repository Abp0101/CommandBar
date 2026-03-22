# CommandBar

> A global AI command bar for macOS. Hit **⌘⌥A** anywhere — a full-width liquid-glass strip slides in, you type, and it either answers you inline or actually *does things* on your Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![Powered by Ollama](https://img.shields.io/badge/AI-Ollama-black)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## What it does

| You type… | CommandBar does… |
|-----------|-----------------|
| `"What's the difference between async/await and GCD?"` | Streams a concise answer inline, then auto-hides |
| `"Open Figma"` | Launches Figma immediately |
| `"Move all PDFs from Downloads to Documents/Archive"` | Shows a step-by-step plan, asks you to confirm, then runs it |
| `"Start my coding environment"` | Runs your saved workflow (open Xcode, Terminal, Spotify) in sequence |
| `"Explain this error: EXC_BAD_ACCESS"` | Gives you a short diagnosis right in the bar |

---

## Core experience

- **⌘⌥A** summons the bar from anywhere — no Dock icon, no switching apps
- Full-width **liquid-glass overlay** (NSVisualEffectView behind-window blur)
- **Streaming AI answers** via Ollama — text appears as it's generated
- **Action planner** — multi-step confirmation with live step progress
- **Saved workflows** — name any sequence and trigger it by phrase
- **Keyboard-first** — Tab, ⎋, ↵ handle everything; no mouse required
- **100% local** — no API keys, no data leaves your machine

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+
- [Ollama](https://ollama.com) running locally

---

## Setup

### 1. Install Ollama

Download from [ollama.com](https://ollama.com) and pull a model:

```bash
ollama pull llama3
```

Make sure Ollama is running — it listens on `localhost:11434` by default.

### 2. Clone

```bash
git clone https://github.com/Abp0101/CommandBar.git
cd CommandBar
```

### 3. Build and run

```bash
swift build
.build/debug/CommandBar
```

Or open in Xcode:

```bash
open Package.swift
```

### 4. Grant permissions

On first launch, macOS will ask for **Accessibility** access (needed for the global hotkey).
Go to **System Settings → Privacy & Security → Accessibility** and enable CommandBar.

Then press **⌘⌥A** anywhere to summon the bar.

---

## Architecture

```
Sources/CommandBar/
├── CommandBarApp.swift              @main entry — Settings scene only (no Dock window)
├── AppDelegate.swift                Menu bar icon, hotkey wiring, window controller setup
├── HotkeyManager.swift              Global ⌘⌥A via Carbon RegisterEventHotKey
├── CommandBarWindowController.swift NSPanel subclass — full-width, above all windows
├── CommandBarView.swift             SwiftUI UI — state machine, text input, animations
├── ActionStep.swift                 Model for a single plan step + status enum
├── AIService.swift                  Ollama API client — intent classification + streaming answers
├── ActionExecutor.swift             NSWorkspace / NSAppleScript execution engine
├── WorkflowStore.swift              JSON-persisted reusable command sequences
├── SettingsView.swift               Preferences: General, Workflows
└── Resources/
    └── Info.plist                   LSUIElement=YES, Accessibility usage strings
```

### State machine (CommandBarView)

```
idle ──[submit]──► thinking ──[is question]──► answering(text)
                          └──[is action]───► planning(steps) ──[confirm]──► executing(i, steps) ──► (auto-dismiss)
```

---

## Customising the hotkey

Open `HotkeyManager.swift` and change the key code and modifier mask:

```swift
// Key codes: kVK_ANSI_A = 0x00, kVK_ANSI_Space = 0x31, etc.
// Modifiers: cmdKey | optionKey | shiftKey | controlKey
RegisterEventHotKey(
    0x00,                           // ← change key code here
    UInt32(cmdKey | optionKey),     // ← change modifiers here
    hotKeyID, ...
)
```

---

## Adding new action handlers

Add a case to `ActionExecutor.execute(step:)`:

```swift
} else if desc.contains("screenshot") {
    await takeScreenshot()
}
```

Then implement the handler using `NSWorkspace`, `NSAppleScript`, or a shell command via `Process`.

---

## Roadmap

- [ ] GUI hotkey picker in Preferences
- [ ] Context awareness — inject selected text automatically
- [ ] Frontmost app context (pass active app to AI for smarter answers)
- [ ] Command history with fuzzy search (↑ / ↓ to cycle)
- [ ] Plugin API for custom Swift action handlers
- [ ] Workflow recorder — "watch what I do" → save as workflow
- [ ] iCloud sync for workflows across Macs
- [ ] Inline image support (screenshots as context)

---

## Permissions summary

| Permission | Why |
|-----------|-----|
| Accessibility | Registering the global ⌘⌥A hotkey |
| Automation / Apple Events | Controlling apps via AppleScript |
| Network | Talking to local Ollama server |

CommandBar never reads your screen, keystrokes, or files unless you explicitly ask it to perform an action involving them.

---

## Contributing

PRs welcome! Please open an issue first for large changes.

1. Fork → branch (`feature/my-thing`) → PR
2. Run `swift build` before opening a PR
3. Follow existing code style (no third-party dependencies unless essential)

---

## License

MIT © 2025 — see [LICENSE](LICENSE)
