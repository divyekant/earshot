import EarshotCore
import SwiftUI

/// Type a command as if you said it. By default the tab only shows what earshot would do (dry run).
struct TestTab: View {
    let store: Store
    let hooks: ManageHooks
    @State private var text = ""
    @State private var runActions = false
    @State private var busy = false
    @State private var report: TestReport?
    @State private var apps: [AppEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Type a command, for example \"open notes\"", text: $text).onSubmit(run)
                Button("Run", action: run).disabled(hooks.test == nil || busy || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Toggle("Also do the action (it can type and click in the front app)", isOn: $runActions)
            Text("earshot never presses Send from this tab unless the command says \"send\".")
                .font(.caption).foregroundStyle(.secondary)
            if hooks.test == nil { NotConnected(what: "The router") }
            if let r = report {
                Form {
                    LabeledContent("Heard", value: r.heard)
                    LabeledContent("Intent", value: IntentText.describe(r.route.intent, apps: apps))
                    LabeledContent("Tier", value: r.route.tier.rawValue)
                    LabeledContent("Confidence", value: String(format: "%.2f%@", r.route.confidence,
                                                                IntentText.belowLine(r.route) ? " (below the line: no action)" : ""))
                    LabeledContent("Router time", value: "\(Int(r.route.ms.rounded())) ms")
                    if !r.route.why.isEmpty { LabeledContent("Why", value: r.route.why) }
                    if !r.route.alternatives.isEmpty {
                        LabeledContent("Also considered", value: r.route.alternatives.prefix(3)
                            .map { IntentText.describe($0, apps: apps) }.joined(separator: "; "))
                    }
                    if let o = r.outcome {
                        LabeledContent("Result", value: (o.ok ? "OK" : "Failed") + (o.note.isEmpty ? "" : ": \(o.note)"))
                        if !o.stages.isEmpty {
                            LabeledContent("Stages", value: o.stages.sorted { $0.value < $1.value }
                                .map { "\($0.key) \(Int($0.value.rounded()))" }.joined(separator: " · "))
                        }
                    } else {
                        LabeledContent("Result", value: "Dry run: no action")
                    }
                }
                .formStyle(.grouped)
                .textSelection(.enabled)
            }
            Spacer()
        }
        .onAppear { apps = store.apps }
    }

    private func run() {
        guard let test = hooks.test else { return }
        let command = text.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        busy = true
        let act = runActions
        Task { @MainActor in
            report = await test(command, act)
            busy = false
        }
    }
}
