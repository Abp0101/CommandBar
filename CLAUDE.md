# CommandBar

macOS menu-bar app (Swift 5.9, macOS 14+, SwiftUI) — global ⌘⌥A liquid-glass command bar powered by Ollama running locally at localhost:11434.

## Build
swift build

## Architecture
- AIService.swift — Ollama API client, streaming via /api/chat
- CommandBarView.swift — SwiftUI state machine (idle → thinking → answering/planning → executing)
- CommandBarWindowController.swift — Full-width NSPanel floating above all windows
- HotkeyManager.swift — Global hotkey via Carbon RegisterEventHotKey
- ActionExecutor.swift — NSWorkspace + NSAppleScript for Mac actions

## Rules
- NO Anthropic API, NO API keys — Ollama only
- No third-party Swift packages — keep dependency-free
- Use async/await throughout, never callbacks
- After every edit run swift build to verify

## Known issues to avoid
- Info.plist must NOT exist in Resources/ folder
- Package.swift must have no resources: or swiftSettings: lines
- RecorderNSButton.coordinator must be fileprivate

## Design
- Follow Apple HIG for macOS
- SF Symbols only for icons
- Liquid glass via NSVisualEffectView .hudWindow material
- Spring animations only: spring(response:dampingFraction:)
- Semantic colors only — dark mode free
