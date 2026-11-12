import Foundation

/// Phase 4, W5: main points of a web page. The package W5 fills this file.
extension Engine {
    func pointsNoText(_ p: PendingPage, reason: String?) {
        output.send(.note(nil, "No text of this page. Nothing to show."))
    }

    func pointsPage(_ p: PendingPage, _ page: WebPageText) {
        output.send(.note(nil, "No text of this page. Nothing to show."))
    }
}
