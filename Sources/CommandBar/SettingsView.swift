import SwiftUI

// MARK: - Root

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General",   systemImage: "gearshape")        }
            APITab()
                .tabItem { Label("Ollama",     systemImage: "cpu")              }
            WorkflowsTab()
                .tabItem { Label("Workflows",  systemImage: "bolt")             }
            HistoryTab()
                .tabItem { Label("History",    systemImage: "clock")            }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {

    @AppStorage("autoHideDelay") private var autoHideDelay: Double = 4
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool   = false
    @AppStorage("injectContext") private var injectContext: Bool   = true

    @State private var keyCombo: KeyCombo = {
        if let data  = UserDefaults.standard.data(forKey: "hotkeyCombo"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) { return combo }
        return .default
    }()

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Trigger shortcut") {
                    HotkeyPickerView(keyCombo: $keyCombo)
                }
            }

            Section("Behaviour") {
                Toggle("Inject selected text as context", isOn: $injectContext)
                Toggle("Show active app badge in bar",    isOn: .constant(true))
                    .disabled(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Answer auto-hide delay: \(autoHideDelay, specifier: "%.0f")s")
                    Slider(value: $autoHideDelay, in: 1...15, step: 1)
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, _ in
                        // Wire to SMAppService on macOS 13+ in a production build
                    }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

// MARK: - Ollama Tab

private struct APITab: View {

    @AppStorage("ollamaHost")  private var host  = "http://localhost:11434"
    @AppStorage("ollamaModel") private var model = "llama3.2"

    @State private var testResult: String? = nil
    @State private var isTesting  = false

    var body: some View {
        Form {
            Section("Ollama") {
                LabeledContent("Host") {
                    TextField("http://localhost:11434", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Model") {
                    TextField("llama3.2", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section {
                HStack {
                    Button(isTesting ? "Testing…" : "Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                    }
                }

                Label("Ollama must be running locally. No API key required.",
                      systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func testConnection() async {
        isTesting  = true
        testResult = nil
        var got    = ""
        await AIService.shared.streamAnswer(
            for:          "Reply with exactly the word: OK",
            appContext:    nil,
            selectedText:  nil
        ) { chunk in
            await MainActor.run { got += chunk }
        }
        isTesting  = false
        testResult = got.contains("⚠️") ? "✗ \(got)" : "✓ Connected"
    }
}

// MARK: - Workflows Tab

private struct WorkflowsTab: View {

    @StateObject private var store = WorkflowStore.shared
    @State private var selection: Workflow.ID?
    @State private var showingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.workflows.isEmpty {
                emptyState
            } else {
                List(store.workflows, selection: $selection) { wf in
                    WorkflowRow(workflow: wf)
                }
                .listStyle(.bordered)
            }

            Divider()

            HStack {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("Add workflow")

                Button {
                    if let id = selection,
                       let wf = store.workflows.first(where: { $0.id == id }) {
                        store.delete(wf); selection = nil
                    }
                } label: { Image(systemName: "minus") }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)
                    .help("Delete selected")

                Spacer()
                Text("\(store.workflows.count) workflow\(store.workflows.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .padding(12)
        .sheet(isPresented: $showingNew) { NewWorkflowSheet(isPresented: $showingNew) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.badge.clock").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No workflows yet").font(.headline)
            Text("Run a multi-step action and tap \"Save as workflow\"\nto trigger it again with a single phrase.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkflowRow: View {
    let workflow: Workflow
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workflow.name).font(.system(size: 13, weight: .medium))
            Text("Trigger: \"\(workflow.trigger)\"  •  \(workflow.steps.count) steps")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct NewWorkflowSheet: View {
    @Binding var isPresented: Bool
    @State private var name    = ""
    @State private var trigger = ""
    @State private var steps   = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workflow").font(.headline)

            LabeledContent("Name") {
                TextField("e.g. Coding Environment", text: $name).textFieldStyle(.roundedBorder)
            }
            LabeledContent("Trigger phrase") {
                TextField("e.g. set up coding", text: $trigger).textFieldStyle(.roundedBorder)
            }
            LabeledContent("Steps") {
                TextEditor(text: $steps)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.3))
            }
            Text("One step per line.").font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    let stepList = steps.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    WorkflowStore.shared.save(Workflow(name: name, trigger: trigger, steps: stepList))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || trigger.isEmpty || steps.isEmpty)
            }
        }
        .padding(24).frame(width: 420)
    }
}

// MARK: - History Tab

private struct HistoryTab: View {

    @StateObject private var store = HistoryStore.shared
    @State private var searchText = ""

    private var filtered: [HistoryEntry] {
        guard !searchText.isEmpty else { return store.entries }
        return store.entries.filter { $0.query.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search history…", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.xmark").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(store.entries.isEmpty ? "No history yet" : "No results")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.wasAction ? "bolt" : "text.bubble")
                            .foregroundStyle(entry.wasAction ? .orange : .blue)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.query).font(.system(size: 13))
                            Text(entry.timestamp, style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered)
            }

            Divider()

            HStack {
                Text("\(store.entries.count) entries").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) { store.clear() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(store.entries.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .padding(0)
    }
}
