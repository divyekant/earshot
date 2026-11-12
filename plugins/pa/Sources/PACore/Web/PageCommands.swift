import Foundation

extension Engine {
    /// Phase 4: a page text message from earshot. The log keeps no text: only the part, the count of blocks and
    /// the reason of an error (a short fixed word of earshot). The keep flow (W4) uses the text.
    func receivePageText(_ m: PageTextMessage) {
        switch m {
        case .part(_, let part, let of, let complete, _, _, let blocks):
            log.write(clock.now, "page-text", ["part": String(part), "of": String(of), "blocks": String(blocks.count),
                                               "complete": complete ? "1" : "0"])
        case .error(_, let reason):
            log.write(clock.now, "page-text-error", ["chars": String(reason.count)])
        }
    }
}
