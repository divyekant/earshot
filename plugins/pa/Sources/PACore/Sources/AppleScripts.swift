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

    // Probe run 2 (spec 6.1): one small event for each message.

    /// The id of the newest message of the unified inbox (the cheap check).
    public static let mailNewestID = #"tell application "Mail" to return id of message 1 of inbox"#
    /// The count of accounts.
    public static let mailAccountCount = #"tell application "Mail" to return count of accounts"#
    /// The id of the newest message of the inbox of account K. `%K%` is a fixed number.
    public static let mailAccountNewestID = #"tell application "Mail" to return id of message 1 of mailbox "INBOX" of account %K%"#
    /// The id of message N of the unified inbox.
    public static let mailIDOne = #"tell application "Mail" to return id of message %N% of inbox"#
    /// The receive date of message N.
    public static let mailDateOne = #"tell application "Mail" to return date received of message %N% of inbox"#
    /// The id and the receive date of message N in one event.
    public static let mailIDDateOne = #"tell application "Mail" to tell message %N% of inbox to return {id, date received}"#
    /// All headers of message N.
    public static let mailAllHeadersOne = #"tell application "Mail" to return all headers of message %N% of inbox"#
    /// The header facts of the bulk filter for message N: the header names, and the values of two headers.
    public static let mailHeaderFactsOne = #"""
        tell application "Mail"
            tell message %N% of inbox
                return {name of headers, content of (headers whose name is "Precedence"), content of (headers whose name is "Auto-Submitted")}
            end tell
        end tell
        """#
    /// All that the reader needs of message N except the text (spec 7.4). The From line comes from the headers.
    public static let mailEnvelopeOne = #"""
        tell application "Mail"
            tell message %N% of inbox
                return {id, message id, subject, date received, was replied to, junk mail status, address of to recipients, address of cc recipients, content of (headers whose name is "From"), name of headers, content of (headers whose name is "Precedence"), content of (headers whose name is "Auto-Submitted")}
            end tell
        end tell
        """#
    /// The plain text of message N.
    public static let mailContentOne = #"tell application "Mail" to return content of message %N% of inbox"#
    /// The ids of the messages A to B of the inbox, in one small event (spec 6.1, step 3).
    public static let mailIDsRange = #"tell application "Mail" to return id of messages %A% thru %B% of inbox"#
    /// The addresses of all Mail accounts (for the setting `owner`).
    public static let mailAccountAddresses = #"tell application "Mail" to return email addresses of every account"#
    /// The front app test of another process: a small event that Mail must answer.
    public static let mailPing = #"tell application "Mail" to return count of accounts"#

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
                             mailNewestID, mailAccountCount, mailAccountNewestID, mailIDOne, mailDateOne, mailIDDateOne,
                             mailAllHeadersOne, mailHeaderFactsOne, mailEnvelopeOne, mailContentOne, mailPing, mailIDsRange, mailAccountAddresses,
                             notesCount, notesLocked, notesNames, notesDates, notesPlainText]

    /// The words that must never be in a script (rule 1).
    public static let forbidden = ["send", "delete", "move", "set ", "make", "save", "reply", "forward", "redirect", "duplicate"]

    /// A script with fixed numbers in place of `%A%` and `%B%`.
    public static func range(_ script: String, _ a: Int, _ b: Int) -> String {
        script.replacingOccurrences(of: "%A%", with: String(max(1, a))).replacingOccurrences(of: "%B%", with: String(max(1, a, b)))
    }

    /// A script with a fixed number in place of `%N%`.
    public static func limited(_ script: String, _ n: Int, account k: Int = 1) -> String {
        script.replacingOccurrences(of: "%N%", with: String(max(1, n)))
            .replacingOccurrences(of: "%K%", with: String(max(1, k)))
    }
}
