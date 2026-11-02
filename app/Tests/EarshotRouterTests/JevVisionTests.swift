import EarshotCore
import Foundation
import XCTest
@testable import EarshotRouter

/// T9: the screenshot fallback with Jev (D-10).
final class JevVisionTests: XCTestCase {
    let shot = VisionShot(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), marks: [1, 2, 5], width: 1440, height: 900)

    func body(_ r: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Any])
    }

    func testOffByDefaultAndSeparateFromTier2() {
        var s = EarshotSettings()
        XCTAssertFalse(s.jevSeesScreen)
        XCTAssertNil(ScreenPickerFactory.make(s, jevKey: "key"))
        // "Ask Jev" (text only) does not turn on the screenshot.
        s.tier2 = .jev
        XCTAssertNil(ScreenPickerFactory.make(s, jevKey: "key"))
        s.jevSeesScreen = true
        XCTAssertNil(ScreenPickerFactory.make(s, jevKey: nil))
        XCTAssertNil(ScreenPickerFactory.make(s, jevKey: " "))
        XCTAssertTrue(ScreenPickerFactory.make(s, jevKey: "key") is JevScreenPicker)
    }

    func testRequestShape() throws {
        let r = try JevScreenPicker(apiKey: "k").makeRequest("click settings", shot: shot)
        XCTAssertEqual(r.value(forHTTPHeaderField: "TypeSafe-Danger-Zone-Images"), "true")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let b = try body(r)
        let state = try XCTUnwrap(b["state"] as? [String: Any])
        XCTAssertEqual(state["command"] as? String, "click settings")
        XCTAssertEqual(state["screenshot"] as? String, JevScreenPicker.asset)
        let assets = try XCTUnwrap(b["assets"] as? [String: Any])
        let a = try XCTUnwrap(assets[JevScreenPicker.asset] as? [String: Any])
        XCTAssertEqual(a["type"] as? String, "image")
        XCTAssertEqual(a["format"] as? String, "jpeg")
        XCTAssertEqual(a["data_base64"] as? String, shot.jpeg.base64EncodedString())
        let q = try XCTUnwrap(b["questions"] as? [String: Any])
        let mark = try XCTUnwrap(q["mark"] as? [String: Any])
        XCTAssertEqual(mark["type"] as? String, "choice")
        let criteria = try XCTUnwrap(mark["criteria"] as? [String: Any])
        XCTAssertEqual(Set(criteria.keys), ["n1", "n2", "n5", "none"])
        let box = try XCTUnwrap(q["where"] as? [String: Any])
        XCTAssertEqual(box["type"] as? String, "box")
        XCTAssertTrue((box["instructions"] as? String)?.contains("click settings") == true)
    }

    func answer(choice: String, probs: [String: Double], box: [String: Double]? = nil) -> Data {
        var answers: [String: Any] = ["mark": ["type": "choice", "choice": choice, "confidence": 0.9, "probabilities": probs]]
        if let box { answers["where"] = ["type": "box", "box": box, "confidence": 0.8] }
        return try! JSONSerialization.data(withJSONObject: ["model": "jev-1.14.0", "answers": answers])
    }

    func testParseMark() {
        let d = answer(choice: "n5", probs: ["n1": 0, "n2": 0, "n5": 1, "none": 0])
        XCTAssertEqual(JevScreenPicker.parse(d, marks: [1, 2, 5]), .mark(5))
    }

    func testParseNoneUsesTheBox() {
        let box = ["top": 0.22, "bottom": 0.79, "left": 0.29, "right": 0.91]
        let d = answer(choice: "none", probs: ["n1": 0, "n2": 0, "n5": 0, "none": 1], box: box)
        XCTAssertEqual(JevScreenPicker.parse(d, marks: [1, 2, 5]), .box(top: 0.22, left: 0.29, bottom: 0.79, right: 0.91))
    }

    func testParseRejectsBadAnswers() {
        // A number that earshot did not draw.
        let d1 = answer(choice: "n3", probs: ["n3": 1])
        XCTAssertEqual(JevScreenPicker.parse(d1, marks: [1, 2, 5]), .none)
        // The choice is not the most probable.
        let d2 = answer(choice: "n1", probs: ["n1": 0.2, "n2": 0.7, "n5": 0.1, "none": 0])
        XCTAssertEqual(JevScreenPicker.parse(d2, marks: [1, 2, 5]), .none)
        // A box with edges out of order or out of range.
        let d3 = answer(choice: "none", probs: ["n1": 0, "n2": 0, "n5": 0, "none": 1],
                        box: ["top": 0.8, "bottom": 0.2, "left": 0.1, "right": 0.3])
        XCTAssertEqual(JevScreenPicker.parse(d3, marks: [1, 2, 5]), .none)
        let d4 = answer(choice: "none", probs: ["n1": 0, "n2": 0, "n5": 0, "none": 1],
                        box: ["top": -0.1, "bottom": 0.2, "left": 0.1, "right": 1.3])
        XCTAssertEqual(JevScreenPicker.parse(d4, marks: [1, 2, 5]), .none)
        XCTAssertEqual(JevScreenPicker.parse(Data("{}".utf8), marks: [1]), .none)
    }

    func testBudgetAndErrors() async {
        let slow = JevScreenPicker(apiKey: "k") { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return (Data(), 200)
        }
        let t0 = Date()
        let r = await slow.pick("click settings", shot: shot, budgetMs: 100)
        XCTAssertEqual(r, .none)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1)

        let error = JevScreenPicker(apiKey: "k") { _ in (Data("{}".utf8), 500) }
        let r2 = await error.pick("click settings", shot: shot, budgetMs: 500)
        XCTAssertEqual(r2, .none)

        let empty = VisionShot(jpeg: Data(), marks: [1], width: 1, height: 1)
        let r3 = await error.pick("click settings", shot: empty, budgetMs: 500)
        XCTAssertEqual(r3, .none)
    }
}
