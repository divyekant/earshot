import Foundation

extension Store {
    /// Phase 4 (spec 9.1): the time of the read and the count of words of the kept text of a web page.
    func migration5() throws {
        try db.transaction {
            for (name, type) in [("text_at", "REAL"), ("text_words", "INTEGER")] {
                let have = try db.query("PRAGMA table_info(doc)").contains { $0[1].text == name }
                if !have { try db.exec("ALTER TABLE doc ADD COLUMN \(name) \(type)") }
            }
            try db.exec("PRAGMA user_version = 5")
        }
    }
}
