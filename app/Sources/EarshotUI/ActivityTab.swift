import EarshotCore
import SwiftUI

/// The last commands, with the router tier and the stage times. The log holds no audio and no field text (R-MD-1).
struct ActivityTab: View {
    let store: Store
    @State private var records: [ActivityRecord] = []
    @State private var selection: ActivityRecord.ID?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(ActivityStats.summaryLine(ActivityStats.summary(records))).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { load() }
            }
            Table(records, selection: $selection) {
                TableColumn("Time") { r in Text(r.at, format: .dateTime.hour().minute().second()) }.width(80)
                TableColumn("") { r in
                    Image(systemName: r.ok ? "checkmark.circle" : "xmark.circle").foregroundStyle(r.ok ? .green : .red)
                }.width(24)
                TableColumn("Heard") { r in Text(r.heard).lineLimit(1) }
                TableColumn("Intent") { r in Text(r.intent).lineLimit(1).foregroundStyle(.secondary) }
                TableColumn("Tier") { r in Text(r.tier.rawValue) }.width(50)
                TableColumn("Total") { r in
                    Text(ActivityStats.total(r).map { "\(Int($0.rounded())) ms" } ?? "–").monospacedDigit()
                }.width(70)
            }
            if let r = records.first(where: { $0.id == selection }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.note.isEmpty ? "No note" : r.note)
                    Text(ActivityStats.stageLine(r)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
        }
        .onAppear(perform: load)
    }

    private func load() { records = Array(ActivityLog(store: store).last(500).reversed()) }
}
