import Foundation

// The data that moves between the modules. No module adds app-specific types here (R-MT-1).

/// One row of the app catalogue. The discovery module builds the rows from the menus of each app.
/// The owner approves or edits a row in the management window (R-MT-2).
public struct AppEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bundleID: String
    /// Spoken names, for example "imessage" and "text" for Messages.
    public var aliases: [String]
    /// True if the app has chats (a "new message" or "switch to" menu item).
    public var isChat: Bool
    public var openChat: OpenChat
    /// Electron apps need AXManualAccessibility before the tree is complete.
    public var electron: Bool
    /// The owner approved this row. Actions use only approved rows.
    public var approved: Bool
    public var enabled: Bool

    public init(id: String, name: String, bundleID: String, aliases: [String] = [], isChat: Bool = false,
                openChat: OpenChat = .none, electron: Bool = false, approved: Bool = false, enabled: Bool = true) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.aliases = aliases; self.isChat = isChat
        self.openChat = openChat; self.electron = electron; self.approved = approved; self.enabled = enabled
    }
}

/// How an app opens a chat by name.
public enum OpenChat: Codable, Hashable, Sendable {
    case none
    /// Press `keys` (from the app's own menu), type the name, then pick the result.
    case switcher(keys: String)
    /// Open a URL. `template` holds "{handle}", for example a deep link that the app registers.
    case link(template: String)
}

/// Where a name came from. The router trusts sources in this order.
public enum NameSource: String, Codable, Sendable { case manual, sidebar, search, contacts }

/// A chat, channel or person that the owner can name.
public struct NameEntry: Codable, Hashable, Sendable {
    public var appID: String
    public var name: String
    public var aliases: [String]
    /// The owner's own chat in this app.
    public var isSelf: Bool
    public var source: NameSource

    public init(appID: String, name: String, aliases: [String] = [], isSelf: Bool = false, source: NameSource) {
        self.appID = appID; self.name = name; self.aliases = aliases; self.isSelf = isSelf; self.source = source
    }
}

/// A clickable or typable element on screen, for voice clicks.
public struct ScreenElement: Codable, Hashable, Sendable {
    public var id: String
    public var role: String
    public var label: String
    public var risky: Bool

    public init(id: String, role: String, label: String, risky: Bool) {
        self.id = id; self.role = role; self.label = label; self.risky = risky
    }
}

public enum ScrollDirection: String, Codable, Sendable { case up, down, top, bottom }

/// What the owner asked for. The router makes one intent. The action module runs it.
public enum Intent: Codable, Hashable, Sendable {
    case none
    case openApp(appID: String)
    case openChat(appID: String, target: String, text: String?)
    case click(elementID: String)
    case typeText(String)
    case scroll(ScrollDirection)
    case back
    /// Only an explicit spoken "send" makes this intent (R-NV-5).
    case send
}

/// Which router tier made the decision.
public enum RouterTier: String, Codable, Sendable { case rules, fuzzy, jev, model, none }

public struct RouteResult: Sendable {
    public var intent: Intent
    /// 0...1. Below SafetyPolicy.minimumConfidence the app shows the result and does nothing.
    public var confidence: Double
    public var tier: RouterTier
    public var ms: Double

    public init(intent: Intent, confidence: Double, tier: RouterTier, ms: Double) {
        self.intent = intent; self.confidence = confidence; self.tier = tier; self.ms = ms
    }
}

/// What the router can see when it decides.
public struct RouteContext: Sendable {
    public var apps: [AppEntry]
    public var names: [NameEntry]
    public var frontBundleID: String?
    /// Elements of the front window, for voice clicks. Empty when not needed.
    public var screen: [ScreenElement]

    public init(apps: [AppEntry], names: [NameEntry], frontBundleID: String? = nil, screen: [ScreenElement] = []) {
        self.apps = apps; self.names = names; self.frontBundleID = frontBundleID; self.screen = screen
    }
}

/// The text of one utterance.
public struct Utterance: Sendable {
    public var text: String
    public var engine: String
    /// From the end of speech (or key release) to the final text.
    public var ms: Double

    public init(text: String, engine: String, ms: Double) { self.text = text; self.engine = engine; self.ms = ms }
}

public struct ActionOutcome: Codable, Sendable {
    public var ok: Bool
    /// A short reason for the log and the feedback note, for example "blocked: risky label".
    public var note: String
    /// Stage times in ms, for example ["front": 20, "chat": 380, "focus": 460].
    public var stages: [String: Double]

    public init(ok: Bool, note: String, stages: [String: Double] = [:]) {
        self.ok = ok; self.note = note; self.stages = stages
    }
}
