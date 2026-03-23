import SwiftUI

// MARK: - State machine

enum BarState: Equatable {
    case idle
    case thinking
    case answering(String)
    case planning([ActionStep])
    case executing(current: Int, steps: [ActionStep])

    static func == (lhs: BarState, rhs: BarState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.thinking, .thinking): return true
        case (.answering(let a), .answering(let b)):  return a == b
        case (.planning(let a), .planning(let b)):    return a == b
        case (.executing(let ci, let sa), .executing(let ci2, let sb)):
            return ci == ci2 && sa == sb
        default: return false
        }
    }
}

// MARK: - Main View

struct CommandBarView: View {

    let onDismiss: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var query             = ""
    @State private var state: BarState  = .idle
    @State private var isExpanded        = false
    @State private var historyIndex      = -1
    @State private var showSuggestions   = true
    @State private var selectedSuggIdx   = 0
    @State private var glowPulse         = false
    @State private var iconBounce        = false

    @FocusState private var isFocused: Bool

    @StateObject private var suggestions = SuggestionEngine.shared
    private let ai       = AIService.shared
    private let executor = ActionExecutor.shared
    private let history  = HistoryStore.shared
    private let context  = ContextCapture.shared

    // MARK: - Icon properties per state

    private var iconName: String {
        switch state {
        case .idle:              return "command"
        case .thinking:          return "sparkles"
        case .answering:         return "text.bubble.fill"
        case .planning:          return "list.bullet.clipboard.fill"
        case .executing:         return "bolt.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:              return .white
        case .thinking:          return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .answering:         return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .planning:          return Color(red: 1.0, green: 0.7, blue: 0.3)
        case .executing:         return Color(red: 1.0, green: 0.55, blue: 0.2)
        }
    }

    private var isThinking: Bool {
        if case .thinking = state { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            glassBackground

            VStack(spacing: 0) {
                inputRow.frame(height: 76)

                if isExpanded {
                    glassDivider
                    expandedPanel
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)),
                                removal:   .opacity.combined(with: .offset(y: -4))
                            )
                        )
                }

                if showSuggestions && !suggestions.suggestions.isEmpty && !isExpanded {
                    glassDivider
                    suggestionList
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -6)),
                                removal:   .opacity
                            )
                        )
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { DispatchQueue.main.async { onHeightChange(geo.size.height) } }
                        .onChange(of: geo.size.height) { _, h in
                            DispatchQueue.main.async { onHeightChange(h) }
                        }
                }
            )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isExpanded)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showSuggestions)
        .onChange(of: isExpanded) { _, expanded in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: expanded ? .commandBarContentVisible : .commandBarContentHidden,
                    object: nil
                )
            }
        }
        .onAppear {
            isFocused = true
            suggestions.update(for: "")
        }
    }

    // MARK: - Glass background

    private var glassBackground: some View {
        ZStack {
            // Base blur
            VisualEffectBackground()

            // Specular highlight — white shimmer along the top edge
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.45)
            )

            // State-tinted inner glow
            RadialGradient(
                colors: [iconColor.opacity(0.07), .clear],
                center: UnitPoint(x: 0.12, y: 0.5),
                startRadius: 0,
                endRadius: 120
            )
            .animation(.easeInOut(duration: 0.4), value: iconColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            // Inner border
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 48, x: 0, y: 20)
        .shadow(color: .black.opacity(0.12), radius: 6,  x: 0, y: 2)
        // Coloured glow under the bar matching state
        .shadow(color: iconColor.opacity(0.12), radius: 32, x: 0, y: 8)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 14) {
            glowingIcon.frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                if let sel = context.selectedText, !sel.isEmpty, state == .idle {
                    selectedTextPill(sel)
                }

                TextField("Ask anything or say what to do…", text: $query)
                    .font(.system(size: 17, weight: .regular))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .focused($isFocused)
                    .onSubmit(handleSubmit)
                    .onChange(of: query) { _, new in
                        historyIndex = -1
                        suggestions.update(for: new)
                        showSuggestions = true
                        selectedSuggIdx = 0
                        NotificationCenter.default.post(name: .commandBarUserActivity, object: nil)
                    }
                    .onKeyPress(.upArrow)   { handleHistoryUp();   return .handled }
                    .onKeyPress(.downArrow) { handleHistoryDown(); return .handled }
                    .onKeyPress(.tab)       { handleTab();         return .handled }
                    .onKeyPress(.escape)    { handleEscape();      return .handled }
            }

            trailingControls
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Glowing icon

    private var glowingIcon: some View {
        ZStack {
            // Bloom layer
            Circle()
                .fill(iconColor.opacity(glowPulse ? 0.22 : 0.12))
                .blur(radius: glowPulse ? 14 : 10)
                .frame(width: 44, height: 44)
                .animation(
                    isThinking
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.4),
                    value: glowPulse
                )

            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .shadow(color: iconColor.opacity(0.9), radius: 4)
                .shadow(color: iconColor.opacity(0.5), radius: 10)
                .scaleEffect(iconBounce ? 1.18 : 1.0)
                .symbolEffect(.variableColor.iterative.reversing, isActive: isThinking)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
        .onChange(of: state) { _, _ in
            // Bounce the icon on every state change
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { iconBounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { iconBounce = false }
            }
            // Start/stop pulse for thinking
            withAnimation { glowPulse = isThinking }
        }
        .onAppear { glowPulse = false }
    }

    // MARK: - Selected text pill

    private func selectedTextPill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.cursor").font(.system(size: 9, weight: .semibold))
            Text(text.prefix(55) + (text.count > 55 ? "…" : "")).lineLimit(1)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.14))
        .clipShape(Capsule())
    }

    // MARK: - Trailing controls

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 8) {
            if case .thinking = state {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
                    .transition(.opacity.combined(with: .scale))
            }

            if let app = context.frontmostApp, state == .idle {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.06))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if !query.isEmpty {
                Button { handleEscape() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Text("⎋")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 2)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: query.isEmpty)
    }

    // MARK: - Glass divider

    private var glassDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    // MARK: - Suggestion list

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.suggestions.enumerated()), id: \.element.id) { i, s in
                Button {
                    query = s.text
                    showSuggestions = false
                    isFocused = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(iconColor(s.kind))
                            .frame(width: 16)
                        Text(s.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if i == selectedSuggIdx {
                            Text("Tab")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    .background(
                        i == selectedSuggIdx
                            ? Color.white.opacity(0.07)
                            : .clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)

                if i < suggestions.suggestions.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func iconColor(_ kind: Suggestion.Kind) -> Color {
        switch kind {
        case .history:  .secondary
        case .workflow: Color(red: 1.0, green: 0.7, blue: 0.3)
        case .example:  Color(red: 0.4, green: 0.7, blue: 1.0)
        }
    }

    // MARK: - Expanded panel

    @ViewBuilder
    private var expandedPanel: some View {
        switch state {
        case .idle, .thinking: EmptyView()
        case .answering(let t): answerView(t)
        case .planning(let s):  planView(steps: s)
        case .executing(let c, let s): executingView(current: c, steps: s)
        }
    }

    private func answerView(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .animation(nil, value: text)
    }

    private func planView(steps: [ActionStep]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Here's my plan — confirm to run:", systemImage: "list.bullet.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(
                                LinearGradient(
                                    colors: [iconColor, iconColor.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .shadow(color: iconColor.opacity(0.5), radius: 4)
                    Text(step.description).font(.system(size: 14))
                }
                .transition(.opacity.combined(with: .offset(x: -8)))
            }

            HStack {
                Button("Cancel") { handleEscape() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Spacer()
                Button("Save as workflow") { saveAsWorkflow(steps) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Button("Run  ↵") { startExecution(steps) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .shadow(color: iconColor.opacity(0.4), radius: 8)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, 4)
        }
    }

    private func executingView(current: Int, steps: [ActionStep]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 10) {
                    stepIcon(step: step, index: i, current: current)
                    Text(step.description)
                        .font(.system(size: 14))
                        .foregroundStyle(i <= current ? .primary : .secondary)
                }
                .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
    }

    @ViewBuilder
    private func stepIcon(step: ActionStep, index: Int, current: Int) -> some View {
        if index < current || step.status == .done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .shadow(color: .green.opacity(0.5), radius: 4)
                .transition(.scale.combined(with: .opacity))
        } else if index == current {
            ZStack {
                Circle()
                    .stroke(iconColor.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        } else {
            Circle()
                .strokeBorder(.secondary.opacity(0.3), lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: - Business logic

    private func handleSubmit() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { onDismiss(); return }

        showSuggestions = false
        history.record(input, wasAction: false)

        if let workflow = WorkflowStore.shared.match(for: input) {
            let steps = workflow.steps.map { ActionStep(description: $0) }
            withAnimation { state = .planning(steps); isExpanded = true }
            return
        }

        // Fast path: "open X" / "launch X" — skip AI entirely
        let lower = input.lowercased()
        for prefix in ["open ", "launch ", "start "] {
            if lower.hasPrefix(prefix) {
                let appName = String(input.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !appName.isEmpty else { break }
                let step = ActionStep(description: "Open \(appName)")
                resetAndDismiss()
                Task { await executor.execute(step: step) }
                return
            }
        }

        state = .thinking

        Task {
            let intent = await ai.classifyIntent(input)

            if intent.isAction {
                await MainActor.run { history.record(input, wasAction: true) }
                let steps = await executor.planSteps(for: input)

                if steps.count == 1, isSingleShotAction(steps[0].description) {
                    await MainActor.run {
                        withAnimation { state = .executing(current: 0, steps: steps); isExpanded = true }
                    }
                    await executor.execute(step: steps[0])
                    try? await Task.sleep(for: .milliseconds(600))
                    await MainActor.run { resetAndDismiss() }
                    return
                }

                // If AI flagged this as outside capabilities, show it as an answer
                if let refusal = steps.first, isRefusal(refusal.description) {
                    await MainActor.run {
                        withAnimation { state = .answering(refusal.description); isExpanded = true }
                    }
                    return
                }

                await MainActor.run {
                    withAnimation { state = .planning(steps); isExpanded = true }
                }
            } else {
                await MainActor.run {
                    withAnimation { state = .answering(""); isExpanded = true }
                }
                await ai.streamAnswer(
                    for: input,
                    appContext: context.frontmostApp,
                    selectedText: context.selectedText
                ) { chunk in
                    await MainActor.run {
                        if case .answering(let ex) = state { state = .answering(ex + chunk) }
                    }
                }
            }
        }
    }

    private func startExecution(_ steps: [ActionStep]) {
        state = .executing(current: 0, steps: steps)
        Task {
            for (i, step) in steps.enumerated() {
                await MainActor.run { state = .executing(current: i, steps: steps) }
                await executor.execute(step: step)
                try? await Task.sleep(for: .milliseconds(600))
            }
            var finished = steps
            for j in finished.indices { finished[j].status = .done }
            await MainActor.run { state = .executing(current: steps.count, steps: finished) }
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run { resetAndDismiss() }
        }
    }

    private func saveAsWorkflow(_ steps: [ActionStep]) {
        let wf = Workflow(
            name: query.prefix(40).description,
            trigger: query,
            steps: steps.map { $0.description }
        )
        WorkflowStore.shared.save(wf)
    }

    private func resetAndDismiss() {
        state = .idle
        isExpanded = false
        query = ""
        onDismiss()
    }

    private func isRefusal(_ description: String) -> Bool {
        let lower = description.lowercased()
        return lower.hasPrefix("cannot") || lower.hasPrefix("can't") ||
               lower.hasPrefix("sorry") || lower.contains("outside commandbar") ||
               lower.contains("outside my capabilities") || lower.contains("not able to")
    }

    private func isSingleShotAction(_ description: String) -> Bool {
        let lower = description.lowercased()
        let singleShotPrefixes = ["open ", "launch ", "start ", "switch to ", "show ", "hide ", "quit ", "close "]
        return singleShotPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private func handleEscape() {
        if isExpanded {
            withAnimation { isExpanded = false; state = .idle; query = "" }
        } else if showSuggestions {
            showSuggestions = false
        } else {
            query = ""
            context.clear()
            onDismiss()
        }
    }

    private func handleHistoryUp() {
        let entries = history.entries
        guard !entries.isEmpty else { return }
        historyIndex = min(historyIndex + 1, entries.count - 1)
        query = entries[historyIndex].query
    }

    private func handleHistoryDown() {
        if historyIndex <= 0 { historyIndex = -1; query = "" }
        else { historyIndex -= 1; query = history.entries[historyIndex].query }
    }

    private func handleTab() {
        guard !suggestions.suggestions.isEmpty else { return }
        query = suggestions.suggestions[min(selectedSuggIdx, suggestions.suggestions.count - 1)].text
        showSuggestions = false
        isFocused = true
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = .hudWindow
        v.blendingMode = .behindWindow
        v.state        = .active
        v.wantsLayer   = true
        v.layer?.cornerRadius = 20
        v.layer?.cornerCurve  = .continuous
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
