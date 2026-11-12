#if os(macOS)
import AppKit
import Foundation
import PACore

/// The notes source of the Mac (spec 10): the Notes app through Apple events, read only. The PA never starts
/// Notes: if Notes does not run, `isRunning` is false and the PA does not read.
public final class AppleNotes: NotesSource {
    static let bundleID = "com.apple.Notes"
    var lastEvent: Date?

    public init() {}

    public var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    func event(_ script: String) throws -> NSAppleEventDescriptor {
        guard isRunning else { throw SourceError("Notes does not run") }
        if let last = lastEvent {
            let wait = AppleMail.pause - Date().timeIntervalSince(last)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        defer { lastEvent = Date() }
        let (out, _, code) = SourceProbe.run(script)
        if let code { throw SourceError("Apple event error \(code)") }
        guard let out else { throw SourceError("no answer") }
        return out
    }

    static func list(_ d: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        d.numberOfItems == 0 ? [] : (1...d.numberOfItems).compactMap { d.atIndex($0) }
    }

    public func notes() throws -> [NoteHeader] {
        let ids = Self.list(try event(AppleScripts.notesAllIDs)).map { $0.stringValue ?? "" }
        let names = Self.list(try event(AppleScripts.notesAllNames)).map { $0.stringValue ?? "" }
        let dates = Self.list(try event(AppleScripts.notesAllDates)).map { $0.dateValue ?? Date(timeIntervalSince1970: 0) }
        let locked = Self.list(try event(AppleScripts.notesAllLocked)).map(\.booleanValue)
        let folders = Self.list(try event(AppleScripts.notesAllFolders)).map { $0.stringValue ?? "" }
        guard names.count == ids.count, dates.count == ids.count, locked.count == ids.count, folders.count == ids.count else {
            throw SourceError("the lists of Notes do not agree")
        }
        return ids.indices.map {
            NoteHeader(id: ids[$0], name: names[$0], modifiedAt: dates[$0], locked: locked[$0], folder: folders[$0])
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func text(id: String) throws -> String {
        try event(AppleScripts.withID(AppleScripts.notesTextByID, id)).stringValue ?? ""
    }
}
#endif
