import Foundation

/// One row of the app table (R-MT-1, R-MT-2). To support an app, add a row to apps.json.
struct AppRow: Codable {
    let id: String
    let name: String
    let say: String?
    let bundleID: String
    let aliases: [String]
    let electron: Bool?
    let openChat: OpenChat
    let typeIntoPrefilled: Bool?
    let benchRuns: Int?
    /// The number of Part B script lines for this app. Half are "me" lines with text.
    let scriptLines: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, say, aliases, electron
        case bundleID = "bundle_id"
        case openChat = "open_chat"
        case typeIntoPrefilled = "type_into_prefilled"
        case benchRuns = "bench_runs"
        case scriptLines = "script_lines"
    }

    var spoken: String { say ?? name }
}

struct OpenChat: Codable {
    /// "switcher": press `keys` to open the app's own search, type the name, then press the `pick` keys.
    /// With no `keys`, the probe finds the search field through accessibility and focuses it.
    /// "link": open a URL from `template`. A link needs a handle in people.json.
    let kind: String
    let template: String?
    /// "digits" removes everything except digits from the handle.
    let handle: String?
    let keys: String?
    /// Keys to press after the name shows in the search field, for example ["return"] or ["down", "return"].
    /// Only "down", "up" and "return" are allowed. Each Return goes through the safety guard.
    let pick: [String]?
    let settleMs: Int?

    enum CodingKeys: String, CodingKey {
        case kind, template, handle, keys, pick
        case settleMs = "settle_ms"
    }
}

struct AppTable: Codable { let apps: [AppRow] }

/// A test contact. By default each app finds the chat by `name`.
/// `handles` can give a different name for one app, or "-" to skip that app.
struct Person: Codable {
    let name: String
    let aliases: [String]?
    let isSelf: Bool?
    let handles: [String: String]
    /// Extra words that show on screen in this person's chat, for the chat check.
    let display: [String]?

    enum CodingKeys: String, CodingKey {
        case name, aliases, handles, display
        case isSelf = "self"
    }

    var me: Bool { isSelf == true }

    /// The text that opens this person's chat in the app, or nil to skip the app.
    /// A switcher app uses the name when people.json gives no handle. A link app needs a handle.
    func handle(for row: AppRow) -> String? {
        if let given = handles[row.id]?.trimmingCharacters(in: .whitespaces), !given.isEmpty {
            if given == "-" { return nil }
            return row.openChat.handle == "digits" ? given.filter(\.isNumber) : given
        }
        return row.openChat.kind == "switcher" ? name : nil
    }
}

struct PeopleFile: Codable { let people: [Person] }

enum Config {
    static func loadApps() throws -> [AppRow] {
        let data = try Data(contentsOf: Paths.apps)
        return try JSONDecoder().decode(AppTable.self, from: data).apps
    }

    static func loadPeople() throws -> [Person] {
        guard FileManager.default.fileExists(atPath: Paths.people.path) else {
            throw ProbeError("probe/people.json does not exist. Run: swift run earshot-probe setup")
        }
        let data = try Data(contentsOf: Paths.people)
        return try JSONDecoder().decode(PeopleFile.self, from: data).people
    }

    static func savePeople(_ people: [Person]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(PeopleFile(people: people)).write(to: Paths.people)
    }

    /// Asks for the test chats in the terminal and writes probe/people.json.
    /// It asks for names only. Each app finds the chat through its own search.
    static func interactiveSetup() throws {
        func ask(_ question: String) -> String {
            print(question, terminator: " ")
            return readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        print("""
        earshot-probe setup
        This writes probe/people.json. Git ignores this file. It stays on this Mac.
        The probe types text only into your own chats. For other people it only focuses the message box.

        """)
        let myName = ask("Your name as it shows in Slack:")
        guard !myName.isEmpty else { throw ProbeError("your name is required") }
        var people = [Person(name: myName,
                             aliases: ["me", "myself"],
                             isSelf: true,
                             handles: [:],
                             display: nil)]

        print("""

        Now add up to 5 real contacts for focus-only tests. The probe never types to them.
        Give each name as you will say it. Press Return on an empty name to finish.
        """)
        for i in 1...5 {
            let name = ask("Contact \(i) name:")
            if name.isEmpty { break }
            people.append(Person(name: name, aliases: nil, isSelf: false, handles: [:], display: nil))
        }
        try savePeople(people)
        print("\nWrote \(Paths.people.path)")
    }
}
