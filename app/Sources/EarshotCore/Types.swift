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
    /// The accessibility role, for example "AXLink", "AXButton" or "AXTextField".
    public var role: String
    public var subrole: String
    public var label: String
    /// The address of a link, if it has one.
    public var url: String?
    /// True for a link inside a heading: a search "result" (E2).
    public var inHeading: Bool
    public var risky: Bool
    /// The frame in screen points. Ordinals ("the second result") sort by position.
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(id: String, role: String, subrole: String = "", label: String, url: String? = nil, inHeading: Bool = false,
                risky: Bool, x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0) {
        self.id = id; self.role = role; self.subrole = subrole; self.label = label; self.url = url
        self.inHeading = inHeading; self.risky = risky; self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// What the front window shows: the app, the page address for a browser, and the elements.
public struct ScreenSnapshot: Codable, Hashable, Sendable {
    public var bundleID: String
    public var windowTitle: String
    public var url: String?
    public var elements: [ScreenElement]
    /// The id of the element that has the keyboard focus, if it is a text field that is not secure.
    /// "type X" with no box name types there.
    public var focusedID: String?

    public init(bundleID: String, windowTitle: String, url: String? = nil, elements: [ScreenElement], focusedID: String? = nil) {
        self.bundleID = bundleID; self.windowTitle = windowTitle; self.url = url; self.elements = elements
        self.focusedID = focusedID
    }
}

public enum ScrollDirection: String, Codable, Sendable { case up, down, top, bottom }

/// What the owner asked for. The router makes one intent. The action module runs it.
public enum Intent: Codable, Hashable, Sendable {
    case none
    case openApp(appID: String)
    /// Open a web address (http or https only) in the default browser (R-NV-7).
    case openURL(String)
    case openChat(appID: String, target: String, text: String?)
    case click(elementID: String)
    /// Type into a field of the screen, for example "search for X" (E2).
    case typeInto(elementID: String, text: String)
    case typeText(String)
    case scroll(ScrollDirection)
    case back
    /// Show and hide numbers on the clickable elements (R-CL-3).
    case showNumbers
    case hideNumbers
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
    /// A short reason for the log, for example "label match" or "jev: unsure rules".
    public var why: String
    /// Other intents that the router also considered, best first. The feedback note can offer them.
    public var alternatives: [Intent]
    /// True only for a bare "type" with no text (intent .none). The app can then type the next turn
    /// into the focused text field. Nothing else sets it.
    public var awaitsText: Bool
    /// True only if the owner said a send phrase after the text ("type see you soon and send"). The router removes
    /// the phrase from the text. The app decides if it presses Send. Only `.send` and this flag can lead to a send (R-NV-5).
    public var sendAfter: Bool

    public init(intent: Intent, confidence: Double, tier: RouterTier, ms: Double, why: String = "", alternatives: [Intent] = [],
                awaitsText: Bool = false, sendAfter: Bool = false) {
        self.intent = intent; self.confidence = confidence; self.tier = tier; self.ms = ms
        self.why = why; self.alternatives = alternatives; self.awaitsText = awaitsText; self.sendAfter = sendAfter
    }
}

/// What the router can see when it decides.
public struct RouteContext: Sendable {
    public var apps: [AppEntry]
    public var names: [NameEntry]
    public var frontBundleID: String?
    /// The front window, for voice clicks. Nil when not needed.
    public var screen: ScreenSnapshot?

    public init(apps: [AppEntry], names: [NameEntry], frontBundleID: String? = nil, screen: ScreenSnapshot? = nil) {
        self.apps = apps; self.names = names; self.frontBundleID = frontBundleID; self.screen = screen
    }
}

/// The text of one utterance.
public struct Utterance: Sendable {
    public var text: String
    public var engine: String
    /// From the end of speech (or key release) to the final text.
    public var ms: Double
    /// The pieces of `text` with their audio times, if the engine gives them (Apple SpeechTranscriber). Else empty.
    public var words: [TimedWord]

    public init(text: String, engine: String, ms: Double, words: [TimedWord] = []) {
        self.text = text; self.engine = engine; self.ms = ms; self.words = words
    }
}

/// One piece of a transcript (about one word) with its audio time (D-11).
/// The times are seconds from the start of the turn (`SpeechEngine.begin`). Audio from before the start
/// (the preroll) has negative times.
public struct TimedWord: Sendable, Equatable {
    /// The text as the engine wrote it, with its spaces and punctuation. The pieces joined give the transcript.
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
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
