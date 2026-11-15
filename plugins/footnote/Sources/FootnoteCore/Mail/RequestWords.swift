import Foundation

/// The word lists of the request flags, version 2 (flags v2 spec, section 4). All lists of the gates and of the new
/// features are in this file. They are set with `build-a` and `design-a` only, never with a sealed holdout.
public enum RequestWords {
    // MARK: Gate 2: the mail is for the owner

    /// Greeting words. "Hi Paul, hi Rosa," gives the names paul and rosa.
    static let greet: Set<String> = ["hi", "hello", "dear", "hey", "morning", "evening", "afternoon", "good", "hiya"]
    /// Titles before a last name ("Dear Mr. Brandt,").
    static let titles: Set<String> = ["mr", "mrs", "ms", "miss", "dr", "prof", "sir", "madam"]
    /// A greeting to a group: the mail names no person.
    static let group: Set<String> = ["all", "everyone", "team", "customer", "customers", "member", "members", "parent",
                                     "parents", "friends", "there", "folks", "resident", "residents", "patient",
                                     "patients", "colleagues", "guest", "guests", "neighbours", "neighbors", "winner",
                                     "sir", "madam", "client", "user", "subscriber", "reader", "both", "you", "y'all"]
    /// Capital words at the start of a sentence that are not a name before a comma.
    static let notNames: Set<String> = ["hi", "hello", "dear", "also", "so", "yes", "no", "thanks", "ok", "well", "sorry",
                                        "great", "good", "morning", "evening", "afternoon", "hey", "however", "today",
                                        "tomorrow", "again", "please", "ps", "sure", "right", "oh", "anyway", "btw",
                                        "fyi", "first", "second", "then", "now", "next", "finally", "otherwise",
                                        "sadly", "luckily", "honestly", "meanwhile", "anyhow", "besides", "still",
                                        "and", "but", "or", "if", "when", "as", "since", "update", "reminder", "note",
                                        "love", "cheers", "regards", "best", "brilliant", "perfect", "lovely", "fine",
                                        "yesterday", "tonight", "here", "there", "this", "that", "actually", "plus",
                                        "thank", "kind", "many", "warm", "with", "see", "speak", "talk", "take", "all",
                                        "just", "quick", "big", "huge", "warmest", "much", "lots"]

    // MARK: Gate 3: who writes

    /// Parts of a role address ("orders@", "no-reply@").
    static let roleAddress: Set<String> = ["noreply", "no", "reply", "donotreply", "info", "service", "services", "sales",
                                           "offers", "offer", "news", "newsletter", "billing", "orders", "order",
                                           "support", "team", "hello", "notify", "notifications", "alerts", "alert",
                                           "accounts", "account", "reception", "bookings", "booking", "tickets",
                                           "receipts", "appointments", "office", "hr", "it", "admin", "contact",
                                           "marketing", "events", "loans", "policies", "counciltax", "bins", "parking",
                                           "roads", "shop", "deals", "winner", "security", "enquiries", "customer",
                                           "care", "help", "mail", "survey", "surveys", "feedback", "updates",
                                           "membership", "members", "admissions", "finance", "payments", "claims",
                                           "renewals", "studio", "store", "club", "community", "promo", "rewards",
                                           "invoices", "accounting", "hiring", "jobs", "careers", "press", "media",
                                           "school", "class", "parents", "pta", "secretary", "desk", "registry", "reviews",
                                           "panel", "kontakt", "advisor", "designer", "partners"]
    /// Words in a display name that show an organization ("Harbour Dental", "Westfield Council").
    static let orgNames: Set<String> = ["bank", "council", "insurance", "dental", "surgery", "library", "team", "home",
                                        "energy", "parcel", "cars", "taxis", "books", "market", "cafe", "café",
                                        "primary", "school", "hr", "it", "office", "travel", "rail",
                                        "deals", "centre", "center", "shop", "store", "group", "ltd", "limited",
                                        "inc", "llc", "plc", "services", "service", "support", "news", "club",
                                        "studio", "gym", "fitness", "clinic", "hospital", "pharmacy", "practice",
                                        "academy", "college", "university", "trust", "fund", "foundation",
                                        "association", "society", "agency", "lettings", "estates", "property",
                                        "garage", "motors", "airways", "airlines", "hotel", "hotels", "tours",
                                        "holidays", "magazine", "times", "daily", "weekly", "media", "studios",
                                        "account", "accounts", "billing", "orders", "the", "and", "&", "of", "for",
                                        "from", "at", "via", "customer", "care", "events", "community", "parish",
                                        "nursery", "kitchen", "bakery", "brewery", "salon", "spa", "vet", "vets",
                                        "dentist", "optician", "opticians", "water", "gas", "broadband", "mobile",
                                        "telecom", "post", "delivery", "express", "logistics", "courier", "cinema",
                                        "theatre", "museum", "gallery", "festival", "online", "survey", "surveys",
                                        "panel", "research", "poll", "broadband", "solutions", "digital"]

    /// Acts that an organization can require (a duty).
    static let acts = ["pay", "confirm", "accept", "renew", "return", "collect", "send us", "bring", "sign", "book",
                       "complete", "submit", "reply", "call us", "contact us", "choose", "select", "tell us",
                       "let us know", "move", "fill", "upload", "provide", "arrange", "cancel", "register", "show",
                       "give us", "read and", "agree", "verify", "settle", "top up", "pick up", "drop off", "update your"]
    /// A time limit, besides a day that the time reader finds.
    static let limit = [" by ", " before ", " until ", "no later than", "within ", "deadline", "is due", "due on",
                        "due by", "expires", "expire", "latest", "at the latest", "or we will", "after that date",
                        "end of the month", "this week", "today", "tomorrow"]
    /// Signs that the mail is about a thing of the owner.
    static let ownerThing = ["your order", "your parcel", "your policy", "your appointment", "your bill", "your account",
                             "your booking", "your card", "your tax", "your lease", "your permit", "your car",
                             "your prescription", "your check-up", "your review", "your child", "your son",
                             "your daughter", "your claim", "your sofa", "your delivery", "your application", "your renewal", "your contract",
                             "your meter", "your payment", "your invoice", "your reservation", "your membership",
                             "your licence", "your license", "your passport", "your visa", "your form",
                             "your subscription ends", "your items", "your loan", "your vehicle", "your tenancy",
                             "your deposit", "amount due", "is due", "invoice", "reference", "account number",
                             "policy number", "items on your card", "on your card", "tax return", "consent form",
                             "permission slip", "appointment", "check-up", "items", "fee"]
    /// Signs of sales and surveys. A mail from an organization with 2 or more of them and no sign of a thing of the
    /// owner gets no flag.
    static let sales = ["% off", "free", "offer", "deal", "discount", "voucher", "save", "win", "sale", "upgrade",
                        "quote in", "limited", "review", "rate", "survey", "opinion", "feedback", "recommend",
                        "subscribe", "sign up", "click", "shop now", "buy now", "order now", "book now", "exclusive",
                        "new arrivals", "members only", "early bird", "last chance", "don't miss", "do not miss",
                        "treat yourself", "prize", "points", "questionnaire", "how did we do", "tell us what you think",
                        "stars", "minutes of your time", "with us", "grant", "earn", "prices"]

    // MARK: New score features

    /// A request with no request word.
    static let implicit = ["from you ", "from you.", "from you,", "from you?", "still needs your", "needs your", "i need your", "i still do not have",
                           "i still don't have", "still waiting for your", "any chance", "would you be able",
                           "it would help if you", "are you able", "tell me by", "let me know by", "i need to know",
                           "i need an answer", "waiting on you", "your ok", "your okay", "your answer", "your go-ahead",
                           "would help a lot if you", "help if you could", "asks you to", "asked you to", "wants you to",
                           "would like you to", "please let me know which", "please let me know when"]
    /// The request is done or taken back.
    static let withdrawn = ["no need", "you do not need to", "you don't need to", "you don't have to", "you do not have to",
                            "nothing to do", "nothing from your side", "forget my mail", "forget my last", "all set",
                            "already", "i booked", "i ordered", "we booked", "as agreed", "thanks for", "thank you for",
                            "got it", "never mind", "ignore my", "all sorted", "sorted", "off your list", "all done",
                            "is done", "was done", "i sent", "i paid", "taken care of", "no longer", "nothing for you",
                            "no changes needed", "nothing needed", "not needed"]
    /// A condition that is an offer, not a request.
    static let offerIf = ["if you have questions", "if you have any", "if a ", "if they are too", "let me know how it",
                          "if you want", "if you would like", "if you'd like", "if you ever", "in case you",
                          "if you need", "should you need", "if this was you", "if it helps", "no pressure",
                          "happy to", "i can send you", "just shout", "if needed"]
    /// A question with no task: small talk ("How are you doing?", "Did you see the moon?").
    static let smallTalk = ["how are you", "how is ", "how was ", "did you see", "did you know", "did you hear",
                            "have you seen", "have you heard", "can you believe", "guess what", "who knew",
                            "isn't it", "is it not", "how about that", "how's ", "do you remember"]

    static func has(_ s: String, _ list: [String]) -> Bool { list.contains { s.contains($0) } }
    static func count(_ s: String, _ list: [String]) -> Int { list.filter { s.contains($0) }.count }

    /// Whole-word match for short sales words ("rate" is not in "separate").
    static func countWords(_ s: String, _ list: [String]) -> Int {
        let padded = " " + s.map { $0.isLetter || $0.isNumber || $0 == "%" || $0 == "'" ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        return list.filter { w in
            let cleaned = w.map { $0.isLetter || $0.isNumber || $0 == "%" || $0 == "'" ? $0 : " " }.reduce(into: "") { $0.append($1) }
            return padded.contains(" " + cleaned + " ") || (w.hasPrefix("%") && s.contains(w))
        }.count
    }

    /// A reference number such as "CT-448812", "HM-30219", "2201 4456" or "order 41794".
    static func hasReference(_ s: String) -> Bool {
        s.range(of: #"\b[A-Z]{1,4}-?[0-9]{3,}\b"#, options: .regularExpression) != nil
            || s.range(of: #"\b[0-9]{4} [0-9]{4}\b"#, options: .regularExpression) != nil
            || s.range(of: #"(?i)\b(order|booking|ref|reference|account|policy|invoice|case|ticket)( no\.?| number)? ?#?[0-9]{4,}"#,
                       options: .regularExpression) != nil
    }

    /// A price with "from" ("from 25 pounds", "from £9"): a sales sign.
    static func hasFromPrice(_ s: String) -> Bool {
        s.range(of: #"(?i)\bfrom (£|\$|€)?[0-9]+([.,][0-9]+)? ?(pounds|euros|dollars|a month|per)?"#, options: .regularExpression) != nil
    }
}
