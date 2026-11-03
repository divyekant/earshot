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

    // E6: one voice profile for each microphone.
    private func profile(_ mic: String?, at seconds: Double, x: Float = 1) -> VoiceProfile {
        VoiceProfile(phrase: "hey atlas", embedding: [x, 0], keywordTokens: [], samples: 5, selfScore: 0.8,
                     createdAt: Date(timeIntervalSince1970: seconds), micID: mic, micName: mic.map { "Mic \($0)" })
    }

    func testVoiceBookKeepsOneProfileForEachMicrophone() {
        var book = VoiceBook()
        XCTAssertNil(book.profile(forMic: "usb"))
        book = book.adding(profile("built-in", at: 100))
        book = book.adding(profile("usb", at: 200))
        XCTAssertEqual(book.profiles.count, 2)
        XCTAssertEqual(book.profile(forMic: "built-in")?.micID, "built-in", "the profile of the microphone in use")
        XCTAssertEqual(book.profile(forMic: "usb")?.micID, "usb")
        XCTAssertEqual(book.profile(forMic: "headset")?.micID, "usb", "a new microphone uses the newest profile")
        XCTAssertEqual(book.profile(forMic: nil)?.micID, "usb")
        XCTAssertTrue(book.hasProfile(forMic: "usb"))
        XCTAssertFalse(book.hasProfile(forMic: "headset"))
        XCTAssertFalse(book.hasProfile(forMic: nil))

        // A new teach step on the same microphone replaces its profile only.
        book = book.adding(profile("built-in", at: 300, x: 0.5))
        XCTAssertEqual(book.profiles.count, 2)
        XCTAssertEqual(book.profile(forMic: "built-in")?.embedding, [0.5, 0])
        XCTAssertEqual(book.newest?.micID, "built-in")
    }

    func testVoiceBookKeepsAtMostFourProfiles() {
        var book = VoiceBook()
        for i in 0..<6 { book = book.adding(profile("mic\(i)", at: Double(i))) }
        XCTAssertEqual(book.profiles.count, VoiceBook.maxProfiles)
        XCTAssertEqual(book.profiles.map(\.micID), ["mic2", "mic3", "mic4", "mic5"], "the oldest profiles go")
    }

    func testOldVoiceFileBecomesABookOfOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(folder: folder)
        // voice.json from before the book: one profile, with no microphone.
        let old = profile(nil, at: 100)
        try store.save(old, VoiceProfile.fileName)
        XCTAssertEqual(store.voiceBook.profiles, [old])
        XCTAssertEqual(store.voiceProfile, old)
        // A teach step on a microphone keeps the old profile beside the new one.
        try store.saveVoiceProfile(profile("usb", at: 200))
        XCTAssertEqual(store.voiceBook.profiles.map(\.micID), [nil, "usb"])
        XCTAssertEqual(store.voiceBook.profile(forMic: "usb")?.micName, "Mic usb")
        try store.saveVoiceProfile(nil)
        XCTAssertTrue(store.voiceBook.profiles.isEmpty, "forget deletes all profiles")
    }

    // E6: the limit of the voice check goes up with the speech length, in a line from 1 s to 2 s.
    func testVoiceRuleLimitGoesUpWithTheLength() {
        let rule = VoiceRule(gate: 0.1, short: 0.35, turn: 0.42)
        XCTAssertEqual(rule.limit(seconds: 0.4), 0.35)
        XCTAssertEqual(rule.limit(seconds: 1.0), 0.35)
        XCTAssertEqual(rule.limit(seconds: 1.5), 0.385, accuracy: 1e-9)
        XCTAssertEqual(rule.limit(seconds: 2.0), 0.42)
        XCTAssertEqual(rule.limit(seconds: 9.0), 0.42)
        let flat = VoiceRule(short: 0.35, turn: 0.42, shortSeconds: 1.5, turnSeconds: 1.5)
        XCTAssertEqual(flat.limit(seconds: 1.4), 0.35)
        XCTAssertEqual(flat.limit(seconds: 1.5), 0.35)
        XCTAssertEqual(flat.limit(seconds: 1.6), 0.42, "no division by zero when the two lengths are the same")
    }

    func testVoiceRuleComesFromTheSettings() throws {
        var s = EarshotSettings()
        XCTAssertEqual(s.voiceRule, VoiceRule(gate: 0.35, short: 0.35, turn: 0.42))
        s.voiceGate = 0.2
        s.voiceThreshold = 0.33
        s.turnVoiceThreshold = 0.45
        XCTAssertEqual(s.voiceRule, VoiceRule(gate: 0.2, short: 0.33, turn: 0.45))
        // A settings.json from before E6 has no gate and no turn limit: the defaults fill them in.
        let old = #"{"mode":"alwaysOn","voiceThreshold":0.33}"#
        let read = try JSONDecoder().decode(EarshotSettings.self, from: Data(old.utf8))
        XCTAssertEqual(read.voiceRule, VoiceRule(gate: 0.35, short: 0.33, turn: 0.42))
    }

    func testTurnVoiceSummary() {
        let turn = TurnVoice(kind: .wake, score: 0.514, seconds: 1.84, audioSeconds: 2.6, limit: 0.42, passed: true, ms: 9.2)
        XCTAssertEqual(turn.summary, "turn voice 0.51 (speech 1.84 s, audio 2.60 s, needs 0.42, 9 ms)")
        let phrase = TurnVoice(kind: .wake, score: 0.41, seconds: 0, audioSeconds: 1.2, limit: 0.35, passed: true, byTurn: false)
        XCTAssertEqual(phrase.summary, "phrase voice 0.41 (turn not checked, audio 1.20 s, needs 0.35)")
        // E6, section 8: the level of the speech and the check against the last turn.
        let goOn = TurnVoice(kind: .followUp, score: 0.23, seconds: 2.8, audioSeconds: 3.28, limit: 0.42, passed: true,
                             ms: 33, level: -31.4, lastTurnScore: 0.712, lastTurnLimit: 0.45, byLastTurn: true)
        XCTAssertEqual(goOn.summary, "turn voice 0.23 (speech 2.80 s, audio 3.28 s, level -31 dB, needs 0.42, 33 ms), "
                       + "last turn 0.71 (needs 0.45, passed)")
        var missed = goOn
        missed.byLastTurn = false
        missed.passed = false
        missed.lastTurnScore = 0.2
        XCTAssertTrue(missed.summary.hasSuffix(", last turn 0.20 (needs 0.45)"), missed.summary)
    }

    func testLastTurnRuleAndSimilarity() {
        let rule = VoiceRule()
        XCTAssertEqual(rule.lastTurn, 0.45)
        XCTAssertEqual(rule.lastTurnMinSeconds, 1.0, "\"send\" alone has less speech: it must pass the profile (D-12)")
        let check = VoiceCheck(score: 0.3, seconds: 2, embedding: [3, 4])
        XCTAssertEqual(check.similarity(to: [4, 3]) ?? 0, 0.96, accuracy: 1e-9)
        XCTAssertNil(check.similarity(to: [1, 2, 3]), "a different length")
        XCTAssertNil(VoiceCheck(score: 0.3, seconds: 2).similarity(to: [1, 2]), "no embedding")
        XCTAssertNil(check.similarity(to: [0, 0]))
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
