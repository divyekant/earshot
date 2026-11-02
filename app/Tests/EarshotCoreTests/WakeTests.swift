import Foundation
import XCTest
@testable import EarshotCore

// R-ON-1, D-11: the wake phrase text rules and the voice profile file.
final class WakeTests: XCTestCase {
    let phrase = "hey jarvis"

    func testStripRemovesThePhrase() {
        XCTAssertEqual(WakePhrase.strip("Hey Jarvis, open Slack.", phrase: phrase), "open Slack.")
        XCTAssertEqual(WakePhrase.strip("hey jarvis open notes", phrase: phrase), "open notes")
        XCTAssertEqual(WakePhrase.strip("Hey, Jarvis. Open notes.", phrase: phrase), "Open notes.")
    }

    func testStripTakesAMisheardPhrase() {
        XCTAssertEqual(WakePhrase.strip("Hey Jervis open notes", phrase: phrase), "open notes")
        XCTAssertEqual(WakePhrase.strip("Jarvis, open notes", phrase: phrase), "open notes", "the first word was lost")
        XCTAssertEqual(WakePhrase.strip("Hey, ear shot. Open notes.", phrase: "hey earshot"), "Open notes.")
    }

    func testStripSkipsAWordBeforeThePhrase() {
        // The speech engine starts before the phrase, so it can hear the end of an earlier word.
        XCTAssertEqual(WakePhrase.strip("So hey Jarvis open notes", phrase: phrase), "open notes")
    }

    func testStripLeavesOtherTextAlone() {
        XCTAssertEqual(WakePhrase.strip("open notes", phrase: phrase), "open notes")
        XCTAssertEqual(WakePhrase.strip("The meeting is at noon", phrase: phrase), "The meeting is at noon")
        XCTAssertEqual(WakePhrase.strip("", phrase: phrase), "")
    }

    func testPhraseAloneGivesNoText() {
        XCTAssertEqual(WakePhrase.strip("Hey Jarvis", phrase: phrase), "")
        XCTAssertEqual(WakePhrase.strip("Hey, Jarvis.", phrase: phrase), "")
    }

    func testWords() {
        XCTAssertEqual(WakePhrase.words("  Hey, JARVIS! "), ["hey", "jarvis"])
        XCTAssertEqual(WakePhrase.words("it's"), ["its"])
        XCTAssertEqual(WakePhrase.words("..."), [])
    }

    func testEditDistance() {
        XCTAssertEqual(WakePhrase.editDistance("heyjarvis", "heyjarvis"), 0)
        XCTAssertEqual(WakePhrase.editDistance("heyjervis", "heyjarvis"), 1)
        XCTAssertEqual(WakePhrase.editDistance("", "abc"), 3)
        XCTAssertEqual(WakePhrase.editDistance("kitten", "sitting"), 3)
    }

    func testProfileMatchesItsPhraseOnly() {
        let p = VoiceProfile(phrase: "Hey Jarvis", embedding: [1, 0], keywordTokens: [], samples: 5, selfScore: 0.8)
        XCTAssertTrue(p.matches(phrase: "hey, jarvis"))
        XCTAssertFalse(p.matches(phrase: "hey computer"))
    }

    func testDefaultSettingsHaveThePhrase() throws {
        // A settings.json from before D-11 has no wake phrase: the default fills it in.
        let old = #"{"mode":"alwaysOn","showFeedback":true}"#
        let s = try JSONDecoder().decode(EarshotSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.mode, .alwaysOn)
        XCTAssertEqual(s.wakePhrase, WakePhrase.defaultPhrase)
        XCTAssertEqual(s.voiceThreshold, 0.45)
    }

    func testVoiceProfileRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        XCTAssertNil(store.voiceProfile)
        let p = VoiceProfile(phrase: "hey jarvis", embedding: [0.6, 0.8], keywordTokens: [["▁HE", "Y"]], samples: 5,
                             selfScore: 0.7)
        try store.saveVoiceProfile(p)
        XCTAssertEqual(store.voiceProfile?.embedding, [0.6, 0.8])
        XCTAssertEqual(store.voiceProfile?.keywordTokens, [["▁HE", "Y"]])
        try store.saveVoiceProfile(nil)
        XCTAssertNil(store.voiceProfile)
        XCTAssertNoThrow(try store.saveVoiceProfile(nil), "deleting a missing profile is not an error")
    }
}
