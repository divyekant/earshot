import EarshotCore
import Foundation
import XCTest

/// T9: the pure rules of the screenshot fallback (D-10).
final class VisionRulesTests: XCTestCase {
    func testOnlyHoldKeyAndNeverSensitive() {
        XCTAssertTrue(VisionRules.mayAsk(enabled: true, mode: .hold, sensitive: false))
        XCTAssertFalse(VisionRules.mayAsk(enabled: false, mode: .hold, sensitive: false))
        XCTAssertFalse(VisionRules.mayAsk(enabled: true, mode: .alwaysOn, sensitive: false))
        XCTAssertFalse(VisionRules.mayAsk(enabled: true, mode: .hold, sensitive: true))
    }

    func testPictureSize() {
        // A 1440 x 900 point window on Retina (2x) becomes 1568 x 980.
        let (w, h) = VisionRules.pictureSize(width: 1440, height: 900, scale: 2)
        XCTAssertEqual(w, 1568)
        XCTAssertEqual(h, 980)
        XCTAssertTrue(VisionRules.sizeOK(w, h))
        // A small window keeps its size. Too small for the API: no picture.
        XCTAssertEqual(VisionRules.pictureSize(width: 400, height: 300, scale: 1).0, 400)
        // E3 step 2: Calculator, 230 x 408 points at scale 1, is scaled up to the API minimum.
        let (cw, ch) = VisionRules.pictureSize(width: 230, height: 408, scale: 1)
        XCTAssertEqual(cw, 280)
        XCTAssertEqual(ch, 497)
        XCTAssertTrue(VisionRules.sizeOK(cw, ch))
        // A very long thin window: the longest side wins.
        XCTAssertLessThanOrEqual(VisionRules.pictureSize(width: 100, height: 3000, scale: 1).1, VisionRules.maxSide)
        XCTAssertFalse(VisionRules.sizeOK(400, 200))
        XCTAssertFalse(VisionRules.sizeOK(1600, 900))
    }

    func testBoxToPoint() throws {
        // Window at (100, 50), 1000 x 800 points. Box in the middle of the right half.
        let w = (x: 100.0, y: 50.0, w: 1000.0, h: 800.0)
        let p = try XCTUnwrap(VisionRules.point(top: 0.4, left: 0.6, bottom: 0.5, right: 0.8, window: w))
        XCTAssertEqual(p.x, 100 + 0.7 * 1000, accuracy: 0.001)
        XCTAssertEqual(p.y, 50 + 0.45 * 800, accuracy: 0.001)
        // E3 step 1: the "Quarterly report" card, 0.34 of the picture.
        XCTAssertNotNil(VisionRules.point(top: 0.22, left: 0.29, bottom: 0.79, right: 0.91, window: w))
        // Too large: not one element.
        XCTAssertNil(VisionRules.point(top: 0, left: 0, bottom: 1, right: 1, window: w))
        // Too small, out of order, out of range.
        XCTAssertNil(VisionRules.point(top: 0.5, left: 0.5, bottom: 0.501, right: 0.6, window: w))
        XCTAssertNil(VisionRules.point(top: 0.5, left: 0.5, bottom: 0.4, right: 0.6, window: w))
        XCTAssertNil(VisionRules.point(top: 0.5, left: 0.5, bottom: 0.6, right: 1.2, window: w))
        XCTAssertNil(VisionRules.point(top: .nan, left: 0.5, bottom: 0.6, right: 0.7, window: w))
    }

    func testNewSettingsDoNotResetOldOnes() throws {
        // A settings.json from before T9: it has no "jevSeesScreen".
        let old = #"{"mode":"hold","holdKeyCode":61,"holdKeyIsModifierOnly":true,"holdKeyModifiers":0,"engine":"apple","#
            + #""parakeetModelPath":"","locale":"en_US","tier2":"jev","tier2BudgetMs":800,"typeIntoOthers":false,"showFeedback":true}"#
        let s = try JSONDecoder().decode(EarshotSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.tier2, .jev)
        XCTAssertEqual(s.tier2BudgetMs, 800)
        XCTAssertEqual(s.engine, .apple)
        XCTAssertFalse(s.typeIntoOthers)
        XCTAssertFalse(s.jevSeesScreen)
        XCTAssertEqual(s.jevScreenBudgetMs, 1500)
        // Round trip.
        var t = s
        t.jevSeesScreen = true
        let back = try JSONDecoder().decode(EarshotSettings.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }
}
