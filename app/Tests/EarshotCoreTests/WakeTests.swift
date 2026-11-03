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

    func testStripTakesTheFormsFromTheLiveTrial() {
        // Live trial 2026-11-02 with "hey atlas": Apple speech wrote these forms. The strict match kept them, so the
        // router saw "Here, at least open slack." and found no command (R-ON-1, D-11).
        let atlas = "hey atlas"
        XCTAssertEqual(WakePhrase.strip("Here, at least open slack.", phrase: atlas, afterWake: true), "open slack.")
        XCTAssertEqual(WakePhrase.strip("He at least open slack.", phrase: atlas, afterWake: true), "open slack.")
        XCTAssertEqual(WakePhrase.strip("Here at least open Safari.", phrase: atlas, afterWake: true), "open Safari.")
        XCTAssertEqual(WakePhrase.strip("Yeah, at least open notes.", phrase: atlas, afterWake: true), "open notes.")
        XCTAssertEqual(WakePhrase.strip("Here, Aglis, open chrome.", phrase: atlas, afterWake: true), "open chrome.")
        XCTAssertEqual(WakePhrase.strip("Here, at least, type.", phrase: atlas, afterWake: true), "type.")
        // The owner said the phrase again in the follow-up window.
        XCTAssertEqual(WakePhrase.strip("He, at least type, this is working so well.", phrase: atlas),
                       "type, this is working so well.")
        XCTAssertEqual(WakePhrase.strip("Hey Travis, open notes", phrase: phrase, afterWake: true), "open notes")
    }

    func testLooseMatchOnlyAtTheStart() {
        let atlas = "hey atlas"
        XCTAssertEqual(WakePhrase.strip("open slack.", phrase: atlas, afterWake: true), "open slack.")
        XCTAssertEqual(WakePhrase.strip("Dude, this is working.", phrase: atlas), "Dude, this is working.")
        XCTAssertEqual(WakePhrase.strip("Add a list to notes", phrase: atlas), "Add a list to notes")
        XCTAssertEqual(WakePhrase.strip("search for atlas", phrase: atlas), "search for atlas", "the last word alone, late")
        XCTAssertEqual(WakePhrase.strip("Hello, open notes", phrase: atlas, afterWake: true), "Hello, open notes")
        // In a follow-up turn, the last word of the phrase alone needs a close match.
        XCTAssertEqual(WakePhrase.strip("compose an email", phrase: "hey computer"), "compose an email")
        XCTAssertEqual(WakePhrase.strip("The meeting is at noon", phrase: phrase, afterWake: true), "The meeting is at noon")
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
        XCTAssertEqual(s.voiceThreshold, 0.35)
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
    // D-11: remove the phrase by time. Live test 2026-11-02: 3 follow-up turns began with "Yeah, let's" for the phrase
    // said again. The edit distance to "heyatlas" is 5, so the text strip kept it.
    private func w(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

    func testCutRemovesAMisheardPhraseByTime() {
        let words = [w("Yeah, ", -0.10, 0.15), w("let's ", 0.15, 0.45), w("open ", 0.70, 0.95), w("the ", 0.95, 1.05),
                     w("Slack.", 1.05, 1.50)]
        // The spotter fired 0.9 s into the follow-up turn, 0.4 s after the phrase end.
        let hit = WakeHit(phrase: "hey atlas", prerollSeconds: 1.3, phraseEndSeconds: 0.4, voiceScore: 0.6, isOwner: true,
                          inTurnAfterSeconds: 0.9)
        XCTAssertEqual(hit.phraseEndInTurn, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WakePhrase.cut(words, phraseEnd: hit.phraseEndInTurn), "open the Slack.")
        XCTAssertEqual(WakePhrase.strip("Yeah, let's open the Slack.", phrase: "hey atlas", afterWake: true),
                       "Yeah, let's open the Slack.", "the text strip alone cannot remove this form")
    }

    func testCutInAWakeTurn() {
        // The turn starts at the wake. The phrase is in the preroll: negative times.
        let hit = WakeHit(phrase: "hey atlas", prerollSeconds: 1.4, phraseEndSeconds: 0.35, voiceScore: 0.6, isOwner: true)
        XCTAssertEqual(hit.phraseEndInTurn, -0.35, accuracy: 1e-9)
        let words = [w("Here, ", -1.2, -0.9), w("at ", -0.9, -0.7), w("least, ", -0.7, -0.4), w("open ", -0.1, 0.2),
                     w("Messages.", 0.2, 0.7)]
        XCTAssertEqual(WakePhrase.cut(words, phraseEnd: hit.phraseEndInTurn), "open Messages.")
    }

    func testCutKeepsACommandWordRightAfterThePhrase() {
        // The phrase end from the spotter is a little late. A command word that starts less than the margin before it
        // stays.
        let words = [w("Hey ", -0.9, -0.6), w("Atlas ", -0.6, -0.4), w("open ", -0.4, -0.1), w("Notes", -0.1, 0.3)]
        XCTAssertEqual(WakePhrase.cut(words, phraseEnd: -0.3), "open Notes")
    }

    func testCutUsesTheStartOfEachPiece() {
        // An engine can let the end of a word run until the next word: "Atlas," ends when "open" starts.
        // A rule on the end of the word would keep "Atlas,".
        let words = [w("Hey ", -1.3, -1.0), w("Atlas, ", -1.0, -0.1), w("open ", -0.1, 0.2), w("Slack", 0.2, 0.6)]
        XCTAssertEqual(WakePhrase.cut(words, phraseEnd: -0.55), "open Slack")
    }

    func testCutNeedsTimesBeforeThePhraseEnd() {
        XCTAssertNil(WakePhrase.cut([], phraseEnd: 0.5), "no times: the text strip decides")
        XCTAssertNil(WakePhrase.cut([w("open ", 0.7, 0.9), w("Slack", 0.9, 1.2)], phraseEnd: 0.5),
                     "no piece before the phrase end: the text strip decides")
        XCTAssertEqual(WakePhrase.cut([w("Hey ", -0.9, -0.6), w("Atlas.", -0.6, -0.3)], phraseEnd: -0.2), "",
                       "the phrase alone gives no text")
    }

    func testNearMissesAdd() {
        var m = NearMisses(count: 2, best: 0.6)
        m.add(NearMisses(count: 1, best: 1.0))
        XCTAssertEqual(m, NearMisses(count: 3, best: 1.0))
        m.add(NearMisses(count: 4, best: 0.5))
        XCTAssertEqual(m, NearMisses(count: 7, best: 1.0))
    }

    // D-11, E5: the audio templates in the voice profile.
    func testNearMissesAddKeepsTheLowestTemplateScore() {
        var m = NearMisses(count: 1, best: 0, bestScore: 0.38)
        m.add(NearMisses(count: 2, best: 0, bestScore: 0.35))
        XCTAssertEqual(m, NearMisses(count: 3, best: 0, bestScore: 0.35))
        m.add(NearMisses(count: 1, best: 0.5))
        XCTAssertEqual(m, NearMisses(count: 4, best: 0.5, bestScore: 0.35), "a spotter near miss has no score")
        var spotter = NearMisses(count: 1, best: 0.5)
        spotter.add(NearMisses(count: 1, best: 0, bestScore: 0.4))
        XCTAssertEqual(spotter.bestScore, 0.4)
    }

    func testOldProfileHasNoTemplates() throws {
        // A voice.json from before the templates: the spelled spotter listens until the owner teaches earshot again.
        let old = #"{"phrase":"hey atlas","embedding":[0.6,0.8],"keywordTokens":[["▁HE","Y"]],"samples":5,"selfScore":0.7,"createdAt":0}"#
        let p = try JSONDecoder().decode(VoiceProfile.self, from: Data(old.utf8))
        XCTAssertNil(p.templates)
        XCTAssertTrue(p.templates(for: "hey atlas").isEmpty)
    }

    func testTemplatesCountOnlyForTheirPhrase() {
        let good = WakeTemplate(frames: 2, width: 3, half: Data(count: 12))
        let broken = WakeTemplate(frames: 2, width: 3, half: Data(count: 5))
        let p = VoiceProfile(phrase: "hey atlas", embedding: [1], keywordTokens: [], samples: 5, selfScore: 0.7,
                             templates: [good, broken, good])
        XCTAssertEqual(p.templates(for: "Hey, Atlas").count, 2, "the broken template is left out")
        XCTAssertTrue(p.templates(for: "hey jarvis").isEmpty, "a new phrase needs new takes")
        XCTAssertTrue(good.isValid)
        XCTAssertFalse(broken.isValid)
        XCTAssertFalse(WakeTemplate(frames: 0, width: 3, half: Data()).isValid)
    }

    func testVoiceProfileWithTemplatesRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        let template = WakeTemplate(frames: 1, width: 2, half: Data([0x00, 0x3C, 0x00, 0xBC]))
        let p = VoiceProfile(phrase: "hey atlas", embedding: [0.6, 0.8], keywordTokens: [], samples: 5, selfScore: 0.7,
                             templates: [template])
        try store.saveVoiceProfile(p)
        XCTAssertEqual(store.voiceProfile?.templates, [template])
        XCTAssertEqual(store.voiceProfile?.templates(for: "hey atlas"), [template])
    }

    func testWakeHitHasNoMatchScoreFromTheSpotter() {
        let hit = WakeHit(phrase: phrase, prerollSeconds: 1, voiceScore: nil, isOwner: true)
        XCTAssertNil(hit.matchScore)
        XCTAssertNil(hit.matchWorst)
        let matched = WakeHit(phrase: phrase, prerollSeconds: 1, voiceScore: 0.6, isOwner: true, matchScore: 0.2, matchWorst: 0.4)
        XCTAssertEqual(matched.matchScore, 0.2)
        XCTAssertEqual(matched.matchWorst, 0.4)
    }
}
