import XCTest
@testable import PACore

/// Flags v2, gates 2 and 3 (v2 spec, section 4). All messages are made up.
final class RequestGateTests: XCTestCase {
    let owner: Set<String> = ["maya", "rao"]
    let addresses: Set<String> = ["maya.rao@example.com"]

    func mail(_ name: String, _ from: String, to: [String] = ["maya.rao@example.com"], subject: String = "note",
              _ body: String) -> MailMessage {
        MailMessage(id: "t", messageID: "<t@x>", fromName: name, fromAddress: from, to: to, cc: [], subject: subject,
                    date: Date(timeIntervalSince1970: 1_800_000_000), listHeader: false, precedence: "",
                    autoSubmitted: false, junk: false, replied: false, text: body)
    }

    func prep(_ m: MailMessage) -> RequestFeatures.Prepared {
        RequestFeatures.prepared(m, owner: owner, ownerAddresses: addresses)
    }

    func testGreetingToAnotherPersonGivesNoSentence() {
        let p = prep(mail("Lena Fox", "lena.fox@example.org", to: ["paul.ng@example.com", "maya.rao@example.com"],
                          "Hi Paul,\n\nCould you send the agenda by Friday?\n\nLena"))
        XCTAssertEqual(p.gate, "greets another")
    }

    func testNameBeforeADashNamesTheAddressee() {
        let p = prep(mail("Ravi Shah", "ravi.shah@example.com", to: ["noah.k@example.com", "maya.rao@example.com"],
                          "Noah - you need to be at the depot by 8. Maya, can you bring the keys on Friday?"))
        XCTAssertNil(p.gate)
        XCTAssertEqual(p.sentences.map(\.text), ["Maya, can you bring the keys on Friday?"])
    }

    func testManyAddressesNeedTheOwnerName() {
        let to = ["a.b@example.com", "c.d@example.com", "e.f@example.com", "maya.rao@example.com"]
        let p = prep(mail("Lena Fox", "lena.fox@example.org", to: to, "Can you send the slides by Friday?"))
        XCTAssertEqual(p.gate, "not for owner")
    }

    func testSalesFromAnOrganizationGetsNoFlag() {
        let m = mail("Bright Broadband", "sales@bright.example.com", "Hello Maya,\n\nCall us this week to book your free upgrade, from 25 pounds a month.")
        XCTAssertTrue(RequestFeatures.isOrganization(m))
        XCTAssertEqual(prep(m).gate, "sales")
    }

    func testOrganizationDutyKeepsTheActSentence() {
        let m = mail("North Library", "loans@north.example.org",
                     "Dear Maya Rao,\n\nCard 2201 4456. Two items on your card are due on 13 November. Return or renew them by that date.")
        let p = prep(m)
        XCTAssertNil(p.gate)
        XCTAssertEqual(p.sentences.map(\.text), ["Return or renew them by that date."])
    }

    func testOrganizationWithNoDutyGetsNoFlag() {
        let m = mail("Kitchen Plan", "designer@kitchenplan.example.com", "Hello Maya,\n\nCan I call you on Thursday to talk about your plans?")
        XCTAssertEqual(prep(m).gate, "no duty")
    }

    func testPersonWithFirstLastAddressIsAPerson() {
        XCTAssertFalse(RequestFeatures.isOrganization(mail("Leo's teacher", "j.marsh@school.example.org", "x")))
    }

    func testSmallTalkScoresLow() {
        let f = RequestFeatures.sentenceFeatures("Did you see the moon tonight?", owner: owner, timeFound: false)
        XCTAssertLessThan(RequestFeatures.handScore(f), 4)
    }

    func testQuestionBeforeSmallLetterEndsSentence() {
        XCTAssertEqual(RequestFeatures.sentences("can you pick up the cake on saturday? they close at 4"),
                       ["can you pick up the cake on saturday?", "they close at 4"])
    }

    func testForwardedBlockIsCut() {
        let lines = RequestFeatures.prepare("See below.\n\n---------- Forwarded message ---------\nPlease send us the form.")
        XCTAssertFalse(lines.contains { $0.contains("form") })
    }
}
