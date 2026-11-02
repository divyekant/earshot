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

    enum CodingKeys: String, CodingKey {
        case id, name, say, aliases, electron
        case bundleID = "bundle_id"
        case openChat = "open_chat"
        case typeIntoPrefilled = "type_into_prefilled"
        case benchRuns = "bench_runs"
    }

    var spoken: String { say ?? name }
}

struct OpenChat: Codable {
    /// "link": open a URL from `template`. "switcher": press `keys`, type the name, press Return.
    let kind: String
    let template: String?
    /// "digits" removes everything except digits from the handle.
    let handle: String?
    let keys: String?
    let settleMs: Int?

    enum CodingKeys: String, CodingKey {
        case kind, template, handle, keys
        case settleMs = "settle_ms"
    }
}

struct AppTable: Codable { let apps: [AppRow] }

/// A test contact. `handles` maps an app id to the name, number or address that app needs.
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
        let myName = ask("Your name as it shows in Slack (for your own DM):")
        let myPhone = ask("Your WhatsApp number with country code, for example +919800000000:")
        let myEmail = ask("Your email for Messages (iMessage) and Mail:")
        var handles: [String: String] = [:]
        if !myName.isEmpty { handles["slack"] = myName }
        if !myPhone.isEmpty { handles["whatsapp"] = myPhone }
        if !myEmail.isEmpty {
            handles["messages"] = myEmail
            handles["mail"] = myEmail
        }
        var people = [Person(name: myName.isEmpty ? "me" : myName,
                             aliases: ["me", "myself"],
                             isSelf: true,
                             handles: handles,
                             display: ["(You)", "You", "Message yourself"])]

        print("""

        Now add up to 5 real contacts for focus-only tests. The probe never types to them.
        Press Return on an empty name to finish. Press Return to skip an app.
        """)
        for i in 1...5 {
            let name = ask("Contact \(i) name, as you will say it:")
            if name.isEmpty { break }
            var h: [String: String] = [:]
            let slack = ask("  Slack name (Return = same as above, '-' = skip):")
            if slack != "-" { h["slack"] = slack.isEmpty ? name : slack }
            let wa = ask("  WhatsApp number (Return = skip):")
            if !wa.isEmpty { h["whatsapp"] = wa }
            let im = ask("  iMessage phone or email (Return = skip):")
            if !im.isEmpty { h["messages"] = im }
            let mail = ask("  Email address (Return = skip):")
            if !mail.isEmpty { h["mail"] = mail }
            people.append(Person(name: name, aliases: nil, isSelf: false, handles: h, display: nil))
        }
        try savePeople(people)
        print("\nWrote \(Paths.people.path)")
    }
}
