import EarshotCore
import SwiftUI

// Activity reads like a diary, not a log (design canvas "Window: Activity"). What earshot did comes first, in plain
// words. What the owner said comes second, in quotes. One row opens to show where the time went. Wake checks with no
// command fold into one line. The log keeps no audio and no typed words (R-MD-1).

/// The filters of the Activity page.
enum ActivityFilter: String, CaseIterable, Hashable {
    case all, done, failed, asked
    var title: String {
        switch self {
        case .all: return "All"
        case .done: return "Done"
        case .failed: return "Did not work"
        case .asked: return "Asked you"
        }
    }
}

/// One line of the diary: a command, or a fold of quiet records.
enum DiaryItem: Identifiable {
    case command(ActivityRecord)
    case quiet([ActivityRecord])

    var id: UUID {
        switch self {
        case .command(let r): return r.id
        case .quiet(let rs): return rs[0].id
        }
    }
    var at: Date {
        switch self {
        case .command(let r): return r.at
        case .quiet(let rs): return rs[0].at
        }
    }
}

public enum Diary {
    /// The records of one day, newest first, with each run of quiet records (no command) folded into one item.
    static func items(_ records: [ActivityRecord]) -> [DiaryItem] {
        var out: [DiaryItem] = []
        var quiet: [ActivityRecord] = []
        for r in records.sorted(by: { $0.at > $1.at }) {
            if PanelText.shows(r) {
                if !quiet.isEmpty { out.append(.quiet(quiet)); quiet = [] }
                out.append(.command(r))
            } else {
                quiet.append(r)
            }
        }
        if !quiet.isEmpty { out.append(.quiet(quiet)) }
        return out
    }

    /// The title of a fold: the dropped wake turns count, else the wake checks.
    static func quietTitle(_ rs: [ActivityRecord], wakePhrase: String) -> String {
        let dropped = rs.filter { $0.note.contains("dropped") }.count
        if dropped > 0 {
            return "Heard “\(wakePhrase)” \(dropped) time\(dropped == 1 ? "" : "s") with no command after it"
        }
        return "\(rs.count) wake phrase check\(rs.count == 1 ? "" : "s"), no command"
    }

    /// True if the record passes the filter.
    static func passes(_ r: ActivityRecord, _ f: ActivityFilter) -> Bool {
        let tone = RecordText.line(r).tone
        switch f {
        case .all: return true
        case .done: return tone == .done
        case .failed: return tone == .failed
        case .asked: return tone == .asked
        }
    }

    /// The day heading: "Today", "Yesterday" or "Thursday".
    static func dayTitle(_ day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: y) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    /// The parts of the time of a command, in order, for the bar: speech, the screen read, the route and the action.
    static func parts(_ r: ActivityRecord) -> [(label: String, ms: Double)] {
        let s = r.stages
        var out: [(String, Double)] = []
        if let v = s["speech"] { out.append(("Speech to text", v)) }
        let read = (s["screen"] ?? 0) + (s["context"] ?? 0) + (s["names"] ?? 0)
        if read > 0 { out.append(("Read the screen", read)) }
        if let v = s["route"] { out.append(("Understand", v)) }
        if let v = s["action.total"] ?? s["plugin.handoff"] ?? s["action.typed"] { out.append(("Act", v)) }
        return out.filter { $0.1 > 0.05 }
    }
}

struct ActivityPage: View {
    let store: Store
    let wakePhrase: String
    let holdKey: String
    var alwaysOn = false
    @State private var records: [ActivityRecord] = []
    @State private var apps: [AppEntry] = []
    @State private var filter: ActivityFilter = .all
    @State private var query = ""
    @State private var open: UUID?
    @State private var loaded = false
    var fixed: [ActivityRecord]?

    var body: some View {
        Group {
            if loaded && records.filter(PanelText.shows).isEmpty {
                EmptyActivity(holdKey: holdKey, wakePhrase: alwaysOn ? wakePhrase : nil)
            } else {
                PageFrame(top: 26) {
                    HStack {
                        PageTabs(selection: $filter, tabs: ActivityFilter.allCases.map { ($0, $0.title) })
                        Spacer()
                        SearchField(text: $query, prompt: "Search what you said")
                    }
                    PageTitle(title: "Activity").padding(.top, 22)
                    summary.padding(.top, 8)
                    diary
                }
            }
        }
        .onAppear(perform: load)
    }

    private var summary: some View {
        let today = records.filter { Calendar.current.isDateInToday($0.at) && PanelText.shows($0) }
        let lines = today.map { RecordText.line($0, apps: apps) }
        let usual = ActivityStats.percentile(today.compactMap(ActivityStats.total), 0.5)
        return HStack(spacing: 18) {
            fact("\(today.count)", "command\(today.count == 1 ? "" : "s") today")
            fact("\(lines.filter { $0.tone == .done }.count)", "done")
            fact("\(lines.filter { $0.tone == .failed }.count)", "did not work")
            fact("\(lines.filter { $0.tone == .asked }.count)", "asked you")
            if let usual { fact("\(Int(usual.rounded())) ms", "usual time") }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).textStyle(TextStyle(13, 18, mono: true), Palette.ink)
            Text(label).textStyle(.call, Palette.ink2)
        }
    }

    private var shown: [ActivityRecord] {
        let q = SafetyPolicy.normalize(query)
        return records.filter { r in
            guard filter == .all || (PanelText.shows(r) && Diary.passes(r, filter)) else { return false }
            guard !q.isEmpty else { return true }
            let line = RecordText.line(r, apps: apps)
            return SafetyPolicy.normalize(r.heard + " " + line.title + " " + line.detail).contains(q)
        }
    }

    @ViewBuilder private var diary: some View {
        let byDay = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.at) }
        let days = byDay.keys.sorted(by: >)
        if days.isEmpty {
            Text(query.isEmpty ? "Nothing here." : "Nothing matches “\(query)”.").textStyle(.body, Palette.ink3).padding(.top, 28)
        }
        ForEach(days, id: \.self) { day in
            HStack {
                Text(Diary.dayTitle(day)).textStyle(TextStyle(12, 16, 600), Palette.ink2)
                Spacer()
                Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).textStyle(.mono, Palette.ink3)
            }
            .padding(.top, 24).padding(.bottom, 6)
            ForEach(Diary.items(byDay[day] ?? [])) { item in
                switch item {
                case .command(let r):
                    CommandRow(record: r, line: RecordText.line(r, apps: apps), open: open == r.id) {
                        withAnimation(Motion.control) { open = open == r.id ? nil : r.id }
                    }
                case .quiet(let rs):
                    QuietRow(title: Diary.quietTitle(rs, wakePhrase: wakePhrase), records: rs)
                }
            }
        }
    }

    private func load() {
        records = fixed ?? Array(ActivityLog(store: store).last(600).reversed())
        apps = store.apps
        loaded = true
    }
}

/// One command in the diary. A click opens where the time went.
struct CommandRow: View {
    let record: ActivityRecord
    let line: RecordLine
    let open: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(MenuPanel.time(record.at)).textStyle(TextStyle(12, 20, mono: true), Palette.ink3).frame(width: 52, alignment: .leading)
                Glyph(line.glyph).foregroundStyle(tone).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.title).textStyle(.body, Palette.ink).lineLimit(open ? 3 : 1)
                    if !line.detail.isEmpty { Text(line.detail).textStyle(.detail, Palette.ink3).lineLimit(open ? 3 : 1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let ms = ActivityStats.total(record) {
                    Text("\(Int(ms.rounded())) ms").textStyle(TextStyle(12, 20, mono: true), Palette.ink3)
                }
            }
            if open { detail.padding(.leading, 52 + 12 + 16 + 12).padding(.top, 12) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(open || hover ? Palette.raise : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(open ? Palette.rule : .clear, lineWidth: 1))
        .padding(.horizontal, -12)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var tone: Color {
        switch line.tone {
        case .failed: return Palette.coral
        case .asked: return Palette.amber
        case .quiet: return Palette.ink4
        case .done: return Palette.ink2
        }
    }

    @ViewBuilder private var detail: some View {
        let parts = Diary.parts(record)
        let total = max(1, parts.map(\.ms).reduce(0, +))
        VStack(alignment: .leading, spacing: 0) {
            if !parts.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                            Rectangle().fill(Self.partColor(i, p.label))
                                .frame(width: max(2, (g.size.width - CGFloat(parts.count - 1) * 2) * p.ms / total))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                .padding(.bottom, 8)
                HStack(spacing: 14) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Self.partColor(i, p.label)).frame(width: 8, height: 8)
                            Text(p.label).textStyle(.small, Palette.ink3)
                            Text("\(Int(p.ms.rounded()))").textStyle(.mono, Palette.ink2)
                        }
                    }
                }
            }
            if !record.note.isEmpty {
                Text(RecordText.reason(record.note).isEmpty ? record.note : record.note)
                    .textStyle(.small, Palette.ink3).lineLimit(3).textSelection(.enabled).padding(.top, 12)
            }
            HStack(spacing: 8) {
                Chip(tierText)
                Chip(record.tier == .jev ? "cloud: Jev" : "on this Mac", tone: record.tier == .jev ? Palette.amber : Palette.ink2)
                Spacer()
                Text("no audio is kept").textStyle(.mono, Palette.ink3)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rule().padding(.top, 0) }
            .padding(.top, 2)
        }
    }

    private var tierText: String {
        switch record.tier {
        case .rules: return "exact match"
        case .fuzzy: return "close match"
        case .jev: return "Jev"
        case .model: return "model"
        case .none: return "no match"
        }
    }

    /// Understand (the route) is ink: the part that earshot decides. The others alternate two grays.
    static func partColor(_ i: Int, _ label: String) -> Color {
        if label == "Understand" { return Palette.ink }
        return i % 2 == 0 ? Palette.ink4 : Palette.ink3
    }
}

/// A fold of records with no command: wake checks and dropped wake turns.
struct QuietRow: View {
    let title: String
    let records: [ActivityRecord]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(MenuPanel.time(records.last?.at ?? Date())).textStyle(TextStyle(12, 20, mono: true), Palette.ink3)
                    .frame(width: 52, alignment: .leading)
                Glyph(.wake).foregroundStyle(Palette.ink4).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).textStyle(.body, Palette.ink2).lineLimit(1)
                    Text(span + " · numbers only, no audio").textStyle(.detail, Palette.ink3).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Glyph(open ? .chevronDown : .chevronRight, size: 14).foregroundStyle(Palette.ink4).padding(.top, 3)
            }
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(records.prefix(40)) { r in
                        Text(MenuPanel.time(r.at) + "  " + r.note).textStyle(TextStyle(11.5, 16, mono: true), Palette.ink3)
                            .lineLimit(1).textSelection(.enabled)
                    }
                }
                .padding(.leading, 52 + 12 + 16 + 12).padding(.top, 8)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .padding(.horizontal, -12)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Motion.control) { open.toggle() } }
    }

    private var span: String {
        guard let first = records.last?.at, let last = records.first?.at else { return "" }
        let a = MenuPanel.time(first), b = MenuPanel.time(last)
        return a == b ? a : "\(a) to \(b)"
    }
}

/// The Activity page before the first command: a lesson. The keycap is the key to press, and three real commands
/// show what to say.
struct EmptyActivity: View {
    let holdKey: String
    var wakePhrase: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Keycap(LiveState.capOnly(holdKey), size: .big).padding(.bottom, 22)
            Text("Nothing here yet").textStyle(.title, Palette.ink)
            Group {
                if let wakePhrase {
                    Text("Say “\(wakePhrase)”, then a command. Or hold \(LiveState.holdWords(holdKey)) and say it. "
                         + "Each command shows here, in plain words.")
                } else {
                    Text("Hold \(LiveState.holdWords(holdKey)), say a command, then let go. Each command shows here, in plain words.")
                }
            }
            .textStyle(TextStyle(13.5, 19), Palette.ink2)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380).padding(.top, 8)
            VStack(spacing: 8) {
                example("Try", "open notes", "")
                example("or", "click reply", " in Mail")
                example("or", "type hello", " in a chat")
            }
            .padding(.top, 26)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func example(_ lead: String, _ say: String, _ rest: String) -> some View {
        (Text(lead + " ").foregroundColor(Palette.ink3)
            + Text("“\(say)”").font(Typeface.font(TextStyle(13.5, 19, 600))).foregroundColor(Palette.ink)
            + Text(rest).foregroundColor(Palette.ink3))
            .textStyle(TextStyle(13.5, 19))
    }
}
