import AppKit
import Foundation

// MARK: - ActionExecutor

/// Translates natural-language requests into macOS actions.
/// Uses AI to generate step descriptions, then runs each step via
/// NSWorkspace (app launching) or NSAppleScript (complex automation).
final class ActionExecutor {

    static let shared = ActionExecutor()

    private let ai = AIService.shared

    // MARK: - Planning

    func planSteps(for query: String) async -> [ActionStep] {
        let descriptions = await ai.generateSteps(for: query)
        return descriptions.map { ActionStep(description: $0) }
    }

    // MARK: - Execution

    func execute(step: ActionStep) async {
        let desc = step.description.lowercased()

        // Dispatch to the right handler based on keywords
        if let appName = extractAppName(from: desc, keywords: ["open", "launch", "start", "switch to"]) {
            await openApp(named: appName)
        } else if desc.contains("finder") || desc.contains("folder") || desc.contains("navigate") {
            await revealInFinder(path: extractPath(from: step.description))
        } else if desc.contains("volume") || desc.contains("mute") {
            await adjustVolume(from: step.description)
        } else if desc.contains("notification") || desc.contains("do not disturb") {
            // AppleScript fallback
            await runAppleScript(description: step.description)
        } else {
            // Generic AppleScript fallback — ask AI to produce a script
            await runAppleScript(description: step.description)
        }
    }

    // MARK: - Concrete actions

    private func openApp(named name: String) async {
        let ws = NSWorkspace.shared
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try bundle ID map
        if let bid = knownBundleID(for: trimmed),
           let url = await MainActor.run(body: { ws.urlForApplication(withBundleIdentifier: bid) }) {
            await MainActor.run { ws.openApplication(at: url, configuration: .init(), completionHandler: nil) }
            return
        }

        // 2. Try Spotlight — finds any installed app by name
        if let url = spotlightFindApp(named: trimmed) {
            await MainActor.run { ws.openApplication(at: url, configuration: .init(), completionHandler: nil) }
            return
        }

        // 3. Scan /Applications and ~/Applications
        let searchDirs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)
            + [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: NSHomeDirectory() + "/Applications")]

        for dir in searchDirs {
            let candidate = dir.appendingPathComponent("\(trimmed).app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                await MainActor.run { ws.openApplication(at: candidate, configuration: .init(), completionHandler: nil) }
                return
            }
        }

        // 4. Last resort
        await MainActor.run { ws.launchApplication(trimmed) }
    }

    private func spotlightFindApp(named name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "kMDItemContentTypeTree == 'com.apple.application-bundle' && kMDItemDisplayName == '\(name)'cd"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let path = output.components(separatedBy: "\n").first(where: { !$0.isEmpty })
        return path.map { URL(fileURLWithPath: $0) }
    }

    private func revealInFinder(path: String?) async {
        await MainActor.run {
            if let p = path, !p.isEmpty {
                let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.launchApplication("Finder")
            }
        }
    }

    private func adjustVolume(from description: String) async {
        let lower = description.lowercased()
        let script: String
        if lower.contains("mute") {
            script = "set volume output muted true"
        } else if lower.contains("unmute") {
            script = "set volume output muted false"
        } else if lower.contains("up") || lower.contains("increase") {
            script = "set volume output volume ((output volume of (get volume settings)) + 10)"
        } else if lower.contains("down") || lower.contains("decrease") {
            script = "set volume output volume ((output volume of (get volume settings)) - 10)"
        } else {
            return
        }
        await runRawAppleScript(script)
    }

    // MARK: - AppleScript helpers

    /// Asks AI to generate a short AppleScript for the described action, then runs it.
    private func runAppleScript(description: String) async {
        // For common patterns we can hard-code safe scripts
        let lower = description.lowercased()

        if lower.contains("empty trash") {
            // Safety: don't auto-empty trash without user confirmation
            return
        }

        // Attempt a simple tell-application pattern
        if let appName = extractAppName(from: lower, keywords: ["tell", "in", "using", "via"]) {
            let script = "tell application \"\(appName)\" to activate"
            await runRawAppleScript(script)
        }
    }

    private func runRawAppleScript(_ source: String) async {
        await MainActor.run {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                NSLog("CommandBar AppleScript error: %@", err)
            }
        }
    }

    // MARK: - Utilities

    private func extractAppName(from text: String, keywords: [String]) -> String? {
        let lower = text.lowercased()
        for kw in keywords {
            if let range = lower.range(of: kw + " ") {
                let after = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Capitalise and strip trailing punctuation
                let name = after
                    .components(separatedBy: .whitespacesAndNewlines).first ?? after
                return name.isEmpty ? nil : name.capitalized
            }
        }
        return nil
    }

    private func extractPath(from text: String) -> String? {
        // Very naive: look for anything starting with / or ~
        let words = text.components(separatedBy: " ")
        return words.first { $0.hasPrefix("/") || $0.hasPrefix("~") }
    }

    private func knownBundleID(for name: String) -> String? {
        let map: [String: String] = [
            "safari":      "com.apple.Safari",
            "mail":        "com.apple.mail",
            "messages":    "com.apple.MobileSMS",
            "facetime":    "com.apple.FaceTime",
            "notes":       "com.apple.Notes",
            "calendar":    "com.apple.iCal",
            "reminders":   "com.apple.reminders",
            "maps":        "com.apple.Maps",
            "music":       "com.apple.Music",
            "podcasts":    "com.apple.podcasts",
            "photos":      "com.apple.Photos",
            "finder":      "com.apple.finder",
            "terminal":    "com.apple.Terminal",
            "xcode":       "com.apple.dt.Xcode",
            "simulator":   "com.apple.iphonesimulator",
            "spotlight":   "com.apple.Spotlight",
            "system preferences": "com.apple.systempreferences",
            "system settings":    "com.apple.systempreferences",
            "activity monitor":   "com.apple.ActivityMonitor",
            "disk utility":       "com.apple.DiskUtility",
            "preview":     "com.apple.Preview",
            "textedit":    "com.apple.TextEdit",
            "calculator":  "com.apple.calculator",
            "spotify":     "com.spotify.client",
            "figma":       "com.figma.Desktop",
            "slack":       "com.tinyspeck.slackmacgap",
            "notion":      "notion.id",
            "arc":         "company.thebrowser.Browser",
            "chrome":      "com.google.Chrome",
            "firefox":     "org.mozilla.firefox",
            "vscode":      "com.microsoft.VSCode",
            "visual studio code": "com.microsoft.VSCode",
            "1password":   "com.1password.1password",
            "zoom":        "us.zoom.xos",
            "discord":     "com.hnc.Discord",
            "linear":      "com.linear",
            "bear":        "net.shinyfrog.bear",
            "obsidian":    "md.obsidian",
        ]
        return map[name.lowercased()]
    }
}
