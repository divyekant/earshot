import Foundation

/// All Apple event scripts of the PA, as fixed texts (phase 3 build spec, rule 1). The PA only reads Mail and Notes.
/// A test reads this file and fails if a script has a word that changes something (`ReadOnlyTests`).
/// A script gets no data from outside: only fixed numbers are put in it (`limited`).
public enum AppleScripts {
    /// The count of messages in the unified inbox of Mail.
    public static let mailInboxCount = #"tell application "Mail" to return count of messages of inbox"#
    /// The ids of the first N messages of the unified inbox. `%N%` is a fixed number.
    public static let mailInboxIDs = #"tell application "Mail" to return id of messages 1 thru %N% of inbox"#
    /// The receive dates of the first N messages, as seconds since 1970 (to test the order).
    public static let mailInboxDates = #"""
        tell application "Mail"
            return date received of messages 1 thru %N% of inbox
        end tell
        """#
    /// All headers of the first N messages.
    public static let mailInboxHeaders = #"tell application "Mail" to return all headers of messages 1 thru %N% of inbox"#
    /// The plain text of the first N messages.
    public static let mailInboxContent = #"tell application "Mail" to return content of messages 1 thru %N% of inbox"#

    /// The count of notes.
    public static let notesCount = #"tell application "Notes" to return count of notes"#
    /// For the first N notes: locked or not.
    public static let notesLocked = #"tell application "Notes" to return password protected of notes 1 thru %N%"#
    /// The names of the first N notes.
    public static let notesNames = #"tell application "Notes" to return name of notes 1 thru %N%"#
    /// The change dates of the first N notes.
    public static let notesDates = #"tell application "Notes" to return modification date of notes 1 thru %N%"#
    /// The plain text of note number N.
    public static let notesPlainText = #"tell application "Notes" to return plaintext of note %N%"#

    /// All scripts, for the read-only test.
    public static let all = [mailInboxCount, mailInboxIDs, mailInboxDates, mailInboxHeaders, mailInboxContent,
                             notesCount, notesLocked, notesNames, notesDates, notesPlainText]

    /// The words that must never be in a script (rule 1).
    public static let forbidden = ["send", "delete", "move", "set ", "make", "save", "reply", "forward", "redirect", "duplicate"]

    /// A script with a fixed number in place of `%N%`.
    public static func limited(_ script: String, _ n: Int) -> String {
        script.replacingOccurrences(of: "%N%", with: String(max(1, n)))
    }
}
