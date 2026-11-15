import EarshotCore
import Foundation

// The board of a plugin (dk, 2026-11-15): a plugin can write its lists as data, in board.json next to its pages.
// earshot then draws them with its own type and rows, in the window and in the panel, so that the plugin looks like
// a part of earshot. The file is optional and needs no manifest key, so the approval does not change
// (docs/PLUGINS.md 5.5). earshot only shows the text: it never runs it as a command (R-PL-3).

/// The lists of a plugin, from <store>/plugin-data/<id>/pages/board.json.
public struct Board: Codable, Equatable, Sendable {
    public var version: Int
    /// A short list for the menu bar panel, for example the to-dos of today.
    public var panel: PanelList?
    /// The pages of the plugin in the window, as tabs.
    public var tabs: [Tab]
    /// The name of the tab with the plugin settings (docs/PLUGINS.md 3.2), for example "Rules". Default "Settings".
    public var settingsTab: String?

    public init(version: Int = 1, panel: PanelList? = nil, tabs: [Tab] = [], settingsTab: String? = nil) {
        self.version = version; self.panel = panel; self.tabs = tabs; self.settingsTab = settingsTab
    }

    public struct PanelList: Codable, Equatable, Sendable {
        public var title: String
        public var rows: [Row]
        /// The line to show when `rows` is empty, or nil to hide the list.
        public var empty: String?
        public init(title: String, rows: [Row], empty: String? = nil) { self.title = title; self.rows = rows; self.empty = empty }
    }

    public struct Tab: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var heading: String?
        public var sub: String?
        /// A short date at the top right, for example "Sat 14 Nov".
        public var date: String?
        public var sections: [Section]
        /// One line at the foot of the page, for example the commands to say.
        public var hint: String?
        public init(id: String, title: String, heading: String? = nil, sub: String? = nil, date: String? = nil,
                    sections: [Section] = [], hint: String? = nil) {
            self.id = id; self.title = title; self.heading = heading; self.sub = sub; self.date = date
            self.sections = sections; self.hint = hint
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public var title: String?
        /// "late" draws the title and the times in coral.
        public var tone: String?
        public var rows: [Row]?
        public var numbers: [Number]?
        /// A plain sentence.
        public var text: String?
        /// The line when `rows` is empty.
        public var empty: String?
        public init(title: String? = nil, tone: String? = nil, rows: [Row]? = nil, numbers: [Number]? = nil,
                    text: String? = nil, empty: String? = nil) {
            self.title = title; self.tone = tone; self.rows = rows; self.numbers = numbers; self.text = text; self.empty = empty
        }
        public var late: Bool { tone == "late" }
    }

    public struct Row: Codable, Equatable, Sendable {
        public var text: String
        /// A short part after the text, for example the project.
        public var detail: String?
        /// A time or a day, at the right.
        public var when: String?
        public var late: Bool?
        /// "todo" (an open circle), "doc", "flag", "note" or nil (no mark).
        public var mark: String?
        /// A file in the pages folder, a document, a folder or an http, https or message address. earshot opens it
        /// with the same rule as "open <target>" (docs/PLUGINS.md 4).
        public var open: String?
        public init(text: String, detail: String? = nil, when: String? = nil, late: Bool? = nil, mark: String? = nil,
                    open: String? = nil) {
            self.text = text; self.detail = detail; self.when = when; self.late = late; self.mark = mark; self.open = open
        }
        public var isLate: Bool { late == true }
    }

    public struct Number: Codable, Equatable, Sendable {
        public var label: String
        public var value: Int
        public init(label: String, value: Int) { self.label = label; self.value = value }
    }

    /// The limits that earshot draws. A larger file is cut, so a plugin cannot make the window slow.
    public static let maxTabs = 8
    public static let maxRows = 200
    public static let maxBytes = 1_000_000

    /// The file name in the pages folder.
    public static let fileName = "board.json"

    /// Reads the board of a pages folder, or nil if there is none or it is not valid.
    public static func read(folder: URL) -> Board? {
        let url = folder.appendingPathComponent(fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size <= maxBytes,
              let data = try? Data(contentsOf: url),
              var board = try? JSONDecoder().decode(Board.self, from: data), board.version == 1 else { return nil }
        board.tabs = Array(board.tabs.prefix(maxTabs))
        for i in board.tabs.indices {
            for j in board.tabs[i].sections.indices {
                if let rows = board.tabs[i].sections[j].rows { board.tabs[i].sections[j].rows = Array(rows.prefix(maxRows)) }
            }
        }
        if let rows = board.panel?.rows { board.panel?.rows = Array(rows.prefix(6)) }
        return board
    }
}

extension PluginPages {
    /// The board of the plugin, or nil.
    public var board: Board? { Board.read(folder: folder) }
}
