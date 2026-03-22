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

    @State private var query              = ""
    @State private var state: BarState   = .idle
    @State private var isExpanded         = false
    @State private var historyIndex       = -1
    @State private var showSuggestions    = true
    @State private var selectedSuggIdx    = 0

    @FocusState private var isFocused: Bool

    @StateObject private var suggestions = SuggestionEngine.shared
    private let ai       = AIService.shared
    private let executor = ActionExecutor.shared
    private let history  = HistoryStore.shared
    private let context  = ContextCapture.shared

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 32, x: 0, y: 12)

            VStack(spacing: 0) {
                inputRow.frame(height: 76)

                if isExpanded {
                    Divider().padding(.horizontal, 18)
                    expandedPanel
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showSuggestions && !suggestions.suggestions.isEmpty && !isExpanded {
                    Divider().padding(.horizontal, 18)
                    suggestionList
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { onHeightChange(geo.size.height) }
                        .onChange(of: geo.size.height) { _, h in onHeightChange(h) }
                }
            )
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: showSuggestions)
        .onAppear {
            isFocused = true
            suggestions.update(for: "")
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(spacing: 14) {
            leadingIcon.frame(width: 26)

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
                    }
                    .onKeyPress(.upArrow)   { handleHistoryUp();   return .handled }
                    .onKeyPress(.downArrow) { handleHistoryDown(); return .handled }
                    .onKeyPress(.tab)       { handleTab();         return .handled }
                    .onKeyPress(.escape)    { handleEscape();      return .handled }
            }

            trailingControls
        }
        .padding(.horizontal, 22)
    }

    private func selectedTextPill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "text.cursor").font(.system(size: 9, weight: .semibold))
            Text(text.prefix(55) + (text.count > 55 ? "…" : "")).lineLimit(1)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: Leading icon

    @ViewBuilder
    private var leadingIcon: some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "command")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .thinking:
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative)
            case .answering:
                Image(systemName: "text.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.purple)
            case .planning, .executing:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Trailing controls

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 8) {
            if case .thinking = state {
                ProgressView().scaleEffect(0.65).frame(width: 18, height: 18)
            }

            if let app = context.frontmostApp, state == .idle {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(app.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.secondary.opacity(0.1))
                .clipShape(Capsule())
            }

            if !query.isEmpty {
                Button { handleEscape() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }

            Text("⎋")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 2)
        }
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
                                .background(.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .background(i == selectedSuggIdx ? Color.accentColor.opacity(0.1) : .clear)
                }
                .buttonStyle(.plain)

                if i < suggestions.suggestions.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconColor(_ kind: Suggestion.Kind) -> Color {
        switch kind {
        case .history:  .secondary
        case .workflow: .orange
        case .example:  .blue
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                    Text(step.description).font(.system(size: 14))
                }
            }

            HStack {
                Button("Cancel") { handleEscape() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Save as workflow") { saveAsWorkflow(steps) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Run  ↵") { startExecution(steps) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, 4)
        }
    }

    private func executingView(current: Int, steps: [ActionStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                HStack(spacing: 10) {
                    stepIcon(step: step, index: i, current: current)
                    Text(step.description).font(.system(size: 14))
                        .foregroundStyle(i <= current ? .primary : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(step: ActionStep, index: Int, current: Int) -> some View {
        if index < current || step.status == .done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if index == current {
            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
        } else {
            Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1.5)
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

        state = .thinking

        Task {
            let intent = await ai.classifyIntent(input)

            if intent.isAction {
                await MainActor.run { history.record(input, wasAction: true) }
                let steps = await executor.planSteps(for: input)
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
            await MainActor.run { onDismiss() }
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
        v.layer?.cornerRadius = 18
        v.layer?.cornerCurve  = .continuous
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
