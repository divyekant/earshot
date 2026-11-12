#!/usr/bin/env python3
"""Write the made-up train and dev fixtures for request flags (PA phase 3, E11).

All names, addresses and texts are made-up. The owner is "Maya Rao".
The label rule is in Tests/PACoreTests/Fixtures/phase3/mail/RULE.md.
This script does not write the holdout. The design thread wrote the holdout.

Run from plugins/pa:
    python3 scripts/make-mail-fixtures.py
The output is the same for each run (fixed seeds).
"""

import json
import os
import random

OUT = os.path.join(os.path.dirname(__file__), "..", "Tests", "PACoreTests", "Fixtures", "phase3", "mail")
OWNER = "maya.rao@example.com"
OWNER_NAME = "Maya Rao"

PEOPLE = [
    ("Sam Lee", "sam.lee@example.org"), ("Priya Shah", "priya.shah@example.net"),
    ("Tom Becker", "tom.becker@example.org"), ("Lena Ortiz", "lena.ortiz@example.com"),
    ("Arjun Mehta", "arjun.mehta@example.net"), ("Grace Kim", "grace.kim@example.org"),
    ("Owen Price", "owen.price@example.com"), ("Nadia Haddad", "nadia.haddad@example.net"),
    ("Ben Novak", "ben.novak@example.org"), ("Chloe Martin", "chloe.martin@example.com"),
    ("Ravi Rao", "ravi.rao@example.net"), ("Anita Rao", "anita.rao@example.org"),
    ("Jonas Weber", "jonas.weber@example.com"), ("Elif Demir", "elif.demir@example.net"),
    ("Marco Rossi", "marco.rossi@example.org"), ("Hana Sato", "hana.sato@example.com"),
    ("Kofi Mensah", "kofi.mensah@example.net"), ("Isla Grant", "isla.grant@example.org"),
    ("Dev Patel", "dev.patel@example.com"), ("Rosa Lima", "rosa.lima@example.net"),
    ("Felix Brandt", "felix.brandt@example.org"), ("Mei Chen", "mei.chen@example.com"),
    ("Liam Walsh", "liam.walsh@example.net"), ("Zara Ahmed", "zara.ahmed@example.org"),
]
COLLEAGUE_DOMAIN = "northwind.example.com"
COLLEAGUES = [
    ("Paul Evans", "paul.evans@" + COLLEAGUE_DOMAIN), ("Sofia Romero", "sofia.romero@" + COLLEAGUE_DOMAIN),
    ("Ken Ito", "ken.ito@" + COLLEAGUE_DOMAIN), ("Amara Obi", "amara.obi@" + COLLEAGUE_DOMAIN),
    ("Erik Lund", "erik.lund@" + COLLEAGUE_DOMAIN), ("Julia Novak", "julia.novak@" + COLLEAGUE_DOMAIN),
]

# Organizations that the owner deals with: (name, address, kind)
ORGS = [
    ("Harbor Lane Lettings", "office@harborlane.example.com", "landlord"),
    ("Elm Park Primary School", "office@elmpark-school.example.org", "school"),
    ("Riverside Tennis Club", "secretary@riversidetc.example.org", "club"),
    ("Brightwater Bank", "noreply@brightwater-bank.example.com", "bank"),
    ("Cedar Mutual Insurance", "service@cedarmutual.example.com", "insurer"),
    ("Kowalski Plumbing", "jan@kowalski-plumbing.example.net", "tradesman"),
    ("Greenfield Dental", "reception@greenfield-dental.example.com", "booking"),
    ("City Council Parking", "noreply@parking.council.example.gov", "council"),
    ("Northside Library", "loans@northside-library.example.org", "library"),
    ("Clearline Energy", "billing@clearline-energy.example.com", "utility"),
]
SHOPS = [
    ("Pinecone Outdoor", "deals@pinecone-outdoor.example.com"),
    ("Lumen Home", "news@lumenhome.example.com"),
    ("Swiftcart", "noreply@swiftcart.example.com"),
    ("Bluepeak Travel", "offers@bluepeak-travel.example.com"),
    ("Daily Grind Coffee", "hello@dailygrind.example.com"),
    ("Mosaic Books", "orders@mosaic-books.example.com"),
]

DEADLINES = [
    "before the 20th", "by Friday", "by 5 pm tomorrow", "no later than 14 November",
    "by the end of the week", "before Monday", "by Thursday morning", "as soon as possible",
    "by 28 November", "before the meeting on Wednesday", "by noon on Tuesday", "on or before 3 December",
]

# Person tasks: (base form, short object name for the "done" form)
TASKS = [
    ("send me the signed form", "the signed form"),
    ("confirm the time for Thursday", "the time"),
    ("check the draft budget", "the draft budget"),
    ("review the slides for the client call", "the slides"),
    ("book a table for six", "the table"),
    ("call the plumber about the leak", "the call"),
    ("share the photos from the trip", "the photos"),
    ("pick up the keys from the office", "the keys"),
    ("fill in the volunteer sheet", "the volunteer sheet"),
    ("update the guest list", "the guest list"),
    ("sign the permission slip", "the permission slip"),
    ("bring the folding chairs", "the chairs"),
    ("return the projector", "the projector"),
    ("look at the quote from the builder", "the quote"),
    ("send the invoice for October", "the invoice"),
    ("add your notes to the shared document", "your notes"),
    ("check the flight times", "the flight times"),
    ("approve the leave request", "the leave request"),
    ("reply to the recruiter", "the reply"),
    ("pay your share of the cabin", "your share"),
    ("forward me the contract", "the contract"),
    ("choose a date for the dinner", "the date"),
    ("test the new login page", "the login page"),
    ("print the tickets", "the tickets"),
]

CONTEXT = [
    "I hope your week is going well.", "It was good to see you on Saturday.",
    "We are almost ready for the weekend.", "The team met this morning to go through the plan.",
    "Things are busy here with the end of the quarter.", "The weather finally changed, so we moved everything inside.",
    "I talked to the others yesterday.", "The kids are still talking about the beach.",
    "We got the numbers from finance last night.", "The venue sent the floor plan today.",
    "My train was late again, so I am writing from the platform.", "Everything else is on track.",
    "The garden looks much better after the rain.", "I attached the latest version.",
    "The new schedule starts next month.", "Most of the group already said yes.",
    "There is a small change to the plan.", "I found the old notes from last year.",
    "The office will be closed on Monday.", "We finished the first part of the move.",
]
CLOSERS = ["Thanks,", "Thank you,", "Best,", "Cheers,", "See you soon,", "Many thanks,", "Regards,", "Love,"]
GREETINGS = ["Hi Maya,", "Hello Maya,", "Dear Maya,", "Hey Maya,", "Maya,", "Dear Ms Rao,", "Hi,", "Hello,"]

SUBJECTS_PERSON = [
    "Quick question", "Saturday", "Next steps", "The form", "Plans for the weekend", "Following up",
    "Dinner", "The trip", "Budget", "Client call", "Small favour", "Thursday", "Update",
    "The keys", "Photos", "Volunteer sheet", "Quote", "Contract", "Tickets", "Guest list",
]


def sentence_request(r, task, deadline):
    """A sentence that asks the reader to do a task. Return the sentence."""
    forms = [
        "Could you {t} {d}?", "Can you {t} {d}?", "Would you {t} {d}?", "Please {t} {d}.",
        "I need you to {t} {d}.", "Can you please {t}?", "Could you {t} when you have a moment?",
        "Please remember to {t} {d}.", "Do not forget to {t} {d}.", "Will you be able to {t} {d}?",
        "Maya, could you {t} {d}?", "When can you {t}?", "Are you able to {t} {d}?",
        "It would help a lot if you could {t} {d}.", "We need you to {t} {d}.",
    ]
    f = r.choice(forms)
    return f.format(t=task, d=deadline)


def sentence_question(r):
    """A question that wants an answer from the owner."""
    return r.choice([
        "Are you free for a call on Thursday afternoon?",
        "Which date works better for you, the 18th or the 25th?",
        "Let me know whether you can come on Saturday.",
        "Do you have the number of the electrician?",
        "Can you tell me how many people are coming?",
        "What time should we meet at the station?",
        "Do you want the vegetarian menu or the standard one?",
        "Let me know by Friday if you want to join.",
        "Which of the two offers do you prefer?",
        "Is the 3 pm slot still good for you?",
    ])


def polite_questions(r):
    return r.choice([
        "How was your trip?", "Hope the move went well?", "Can you believe it is November already?",
        "How are the kids?", "Did you enjoy the concert?", "Who knew the café would be so full?",
        "Isn't the new bridge great?", "How is the new job going?",
    ])


def signature(r, name):
    first = name.split()[0]
    kind = r.random()
    if kind < 0.4:
        return first
    if kind < 0.6:
        return first + "\n\nSent from my phone"
    if kind < 0.8:
        return "-- \n" + name + "\n+44 20 7946 0" + str(r.randint(100, 999))
    return name


def compose(r, greeting, sentences, closer, sig, quoted=None):
    """Join the parts of a mail body. Each sentence stays on its own, so the label is exact."""
    paras = []
    if greeting:
        paras.append(greeting)
    # Put the sentences in one or two paragraphs.
    if len(sentences) > 3 and r.random() < 0.6:
        cut = r.randint(1, len(sentences) - 1)
        paras.append(" ".join(sentences[:cut]))
        paras.append(" ".join(sentences[cut:]))
    else:
        paras.append(" ".join(sentences))
    tail = (closer + "\n" + sig) if closer else sig
    paras.append(tail)
    body = "\n\n".join(paras)
    if quoted:
        body += "\n\n" + quoted
    return body


def quote_block(r, text, who=OWNER_NAME, addr=OWNER):
    day = r.choice(["Mon", "Tue", "Wed", "Thu", "Fri"])
    head = "On {d}, {n} Nov 2026 at {h}:{m:02d}, {who} <{a}> wrote:".format(
        d=day, n=r.randint(1, 11), h=r.randint(8, 20), m=r.randint(0, 59), who=who, a=addr)
    lines = [("> " + ln) if ln else ">" for ln in text.split("\n")]
    return head + "\n" + "\n".join(lines)


class Gen:
    def __init__(self, seed, prefix):
        self.r = random.Random(seed)
        self.prefix = prefix
        self.n = 0
        self.rows = []
        self.labels = []

    def date(self):
        r = self.r
        return "2026-{m:02d}-{d:02d}T{h:02d}:{mi:02d}:00Z".format(
            m=r.choice([10, 11]), d=r.randint(1, 28), h=r.randint(6, 21), mi=r.randint(0, 59))

    def add(self, kind, request, sentence, sentence2, **f):
        self.n += 1
        mid = "{}{:03d}".format(self.prefix, self.n)
        row = {
            "id": mid, "from_name": f.get("from_name", ""), "from_address": f.get("from_address", ""),
            "to": f.get("to", [OWNER]), "cc": f.get("cc", []), "subject": f.get("subject", ""),
            "date": f.get("date") or self.date(), "list_unsubscribe": f.get("list_unsubscribe", False),
            "precedence": f.get("precedence", ""), "auto_submitted": f.get("auto_submitted", False),
            "junk": f.get("junk", False), "replied": f.get("replied", False), "body": f["body"],
        }
        for s in (sentence, sentence2):
            if s:
                assert s in row["body"], (mid, s)
        self.rows.append(row)
        self.labels.append((mid, request, kind, sentence or "", sentence2 or ""))

    # ---------- messages with a request ----------

    def person_request(self, long=False, colleague=False):
        r = self.r
        name, addr = r.choice(COLLEAGUES if colleague else PEOPLE)
        task, _ = r.choice(TASKS)
        req = sentence_request(r, task, r.choice(DEADLINES))
        ctx = r.sample(CONTEXT, r.randint(3, 6) if long else r.randint(0, 2))
        sents = ctx + [req] if long else (ctx[:1] + [req] + ctx[1:])
        second = None
        if r.random() < 0.25:
            second = sentence_question(r)
            sents.append(second)
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        subj = r.choice(SUBJECTS_PERSON)
        cc = [r.choice(PEOPLE)[1]] if r.random() < 0.2 else []
        self.add("person_long" if long else ("work" if colleague else "person"), 1, req, second,
                 from_name=name, from_address=addr, subject=subj, cc=cc, body=body)

    def person_question(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        q = sentence_question(r)
        ctx = r.sample(CONTEXT, r.randint(0, 2))
        body = compose(r, r.choice(GREETINGS), ctx + [q], r.choice(CLOSERS), signature(r, name))
        self.add("question", 1, q, None, from_name=name, from_address=addr,
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def reply_chain_request(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        task, _ = r.choice(TASKS)
        req = sentence_request(r, task, r.choice(DEADLINES))
        new = [r.choice(["Thanks for the update.", "That works for me.", "Good news, the room is free."]), req]
        old = "Hi " + name.split()[0] + ",\n\nThe plan is fine with me. " + r.choice(CONTEXT) + "\n\nMaya"
        body = compose(r, "Hi Maya,", new, r.choice(CLOSERS), name.split()[0], quoted=quote_block(r, old))
        self.add("reply_chain", 1, req, None, from_name=name, from_address=addr,
                 subject="Re: " + r.choice(SUBJECTS_PERSON), body=body)

    def cc_named_request(self):
        r = self.r
        name, addr = r.choice(COLLEAGUES)
        other_name, other_addr = r.choice([c for c in COLLEAGUES if c[1] != addr])
        task, _ = r.choice(TASKS)
        req = "Maya, could you " + task + " " + r.choice(DEADLINES) + "?"
        sents = ["Hi " + other_name.split()[0] + " and Maya,", r.choice(CONTEXT), req]
        body = compose(r, None, sents, r.choice(CLOSERS), name.split()[0])
        self.add("cc_named", 1, req, None, from_name=name, from_address=addr,
                 to=[other_addr], cc=[OWNER], subject=r.choice(SUBJECTS_PERSON), body=body)

    def org_request(self):
        r = self.r
        org, addr, kind = r.choice(ORGS)
        d = r.choice(["25 November", "30 November", "3 December", "Friday 21 November", "the end of the month"])
        acts = {
            "landlord": [("Please confirm a time for the gas safety check before " + d + ".", None),
                         ("Your tenancy ends on 31 December, so please sign the renewal by " + d + ".", None)],
            "school": [("Please sign and return the trip form by " + d + ".", None),
                       ("Parents need to book a meeting slot before " + d + ".", "Use the link in the parent portal to choose a time.")],
            "club": [("Please renew your membership by " + d + " to keep your court bookings.", None),
                     ("Please pay the annual fee of 120 pounds before " + d + ".", None)],
            "bank": [("Please confirm your new address in the app by " + d + ".", None),
                     ("You need to sign the updated account terms before " + d + ".", None)],
            "insurer": [("Your home policy ends on " + d + ", so please renew it before that date.", None),
                        ("Please send us a photo of the damage by " + d + " so we can close the claim.", None)],
            "tradesman": [("Can you confirm that Tuesday at 8 am is fine for the boiler work?", None),
                          ("Please pay the deposit of 200 pounds before " + d + " so I can order the parts.", None)],
            "booking": [("Please confirm your appointment on " + d + " or call us to change it.", None),
                        ("Please bring your insurance card to your visit on " + d + ".", None)],
            "council": [("Please pay the parking charge of 35 pounds by " + d + ".", None),
                        ("You must renew your resident permit before " + d + ".", None)],
            "library": [("Please return the 2 overdue books by " + d + ".", None),
                        ("Please collect your reserved book before " + d + ".", None)],
            "utility": [("Please pay your bill of 84.20 pounds by " + d + ".", None),
                        ("Please send us a meter reading before " + d + ".", None)],
        }
        req, req2 = r.choice(acts[kind])
        intro = r.choice([
            "This is a message about your account.", "We are writing about your next visit.",
            "Thank you for being with us.", "We have an update for you.", "This is a reminder.",
        ])
        sents = [intro, req] + ([req2] if req2 else []) + [r.choice([
            "If you have any questions, call us on 0161 496 0000.", "Thank you.", "We are here to help.",
        ])]
        greet = r.choice(["Dear Ms Rao,", "Dear Maya Rao,", "Hello Maya,", "Dear customer,"])
        body = compose(r, greet, sents, "Kind regards,", org)
        self.add("org_" + kind, 1, req, req2, from_name=org, from_address=addr,
                 subject=r.choice(["Action needed", "Reminder", "Your account", "Your visit", "Please read", org]),
                 body=body)

    # ---------- messages with no request: easy ----------

    def newsletter(self):
        r = self.r
        name, addr = r.choice(SHOPS + [(o[0], o[1]) for o in ORGS[:3]])
        sents = [r.choice(["Here is the news of the month.", "Welcome to our autumn letter.", "Our new range is here."]),
                 r.choice(CONTEXT), r.choice(["Read more on our site.", "Shop the new range today.", "See you next month."])]
        body = compose(r, r.choice(["Hi Maya,", "Hello,", None]), sents, None, "The " + name + " team\n\nUnsubscribe")
        self.add("newsletter", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(["November news", "New this week", "Our autumn letter"]),
                 list_unsubscribe=True, precedence=r.choice(["", "bulk", "list"]), body=body)

    def receipt(self):
        r = self.r
        name, addr = r.choice(SHOPS)
        n = r.randint(10000, 99999)
        sents = ["Thank you for your order " + str(n) + ".", "We received your payment of " + str(r.randint(9, 240)) + ".99 pounds.",
                 r.choice(["Your parcel leaves our store today.", "Your order is complete.", "Keep this mail for your records."])]
        body = compose(r, "Hello Maya,", sents, None, name)
        self.add("receipt", 0, None, None, from_name=name, from_address=addr,
                 subject="Your order " + str(n), body=body)

    def news_person(self):
        r = self.r
        name, addr = r.choice(PEOPLE)
        sents = r.sample(CONTEXT, r.randint(2, 4)) + [r.choice([
            "We finally booked the trip to Lisbon.", "The baby sleeps through the night now.",
            "I start the new job in January.", "The house sale went through on Monday."])]
        r.shuffle(sents)
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        self.add("news", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(["News", "Catching up", "Hello from us"]), body=body)

    def thanks(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        _, obj = r.choice(TASKS)
        sents = [r.choice(["Thanks for " + obj + ".", "Thank you so much for " + obj + ".", "Many thanks for " + obj + "."]),
                 r.choice(["It was a great help.", "Everything is fine now.", "You saved us a lot of time."])]
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        self.add("thanks", 0, None, None, from_name=name, from_address=addr, subject="Thank you", body=body)

    def from_owner(self):
        r = self.r
        name, addr = r.choice(PEOPLE)
        task, _ = r.choice(TASKS)
        req = sentence_request(r, task, r.choice(DEADLINES))
        body = compose(r, "Hi " + name.split()[0] + ",", [r.choice(CONTEXT), req], "Thanks,", "Maya")
        self.add("from_owner", 0, None, None, from_name=OWNER_NAME, from_address=OWNER, to=[addr],
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def auto_reply(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        sents = ["I am out of the office until 24 November.", "For urgent questions, please call the front desk."]
        body = compose(r, None, sents, None, name)
        self.add("auto_reply", 0, None, None, from_name=name, from_address=addr,
                 subject="Automatic reply: " + r.choice(SUBJECTS_PERSON), auto_submitted=True,
                 precedence=r.choice(["", "auto_reply"]), body=body)

    def replied(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        task, _ = r.choice(TASKS)
        req = sentence_request(r, task, r.choice(DEADLINES))
        body = compose(r, r.choice(GREETINGS), [r.choice(CONTEXT), req], r.choice(CLOSERS), signature(r, name))
        self.add("replied", 0, None, None, from_name=name, from_address=addr, replied=True,
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def list_mail(self):
        r = self.r
        name, addr = r.choice(PEOPLE)
        task, _ = r.choice(TASKS)
        req = sentence_request(r, task, r.choice(DEADLINES))
        body = compose(r, "Hi all,", [r.choice(CONTEXT), req], r.choice(CLOSERS), name.split()[0])
        self.add("list", 0, None, None, from_name=name, from_address=addr, to=["parents-class3@lists.example.org"],
                 subject="[Class 3] " + r.choice(SUBJECTS_PERSON), list_unsubscribe=True, precedence="list", body=body)

    # ---------- messages with no request: hard ----------

    def ad_command(self):
        r = self.r
        name, addr = r.choice(SHOPS)
        cmd = r.choice([
            "Buy now and save 20% before Sunday.", "Confirm your subscription to get the weekly deals.",
            "Book your winter break by 30 November and get a free upgrade.", "Order today and get free delivery until Friday.",
            "Renew your plan now to keep the low price.", "Please reply to tell us what you think of our new shop.",
            "Take our 2 minute survey before 5 December.", "Sign up by Friday to win a weekend for two.",
        ])
        sents = [r.choice(["Our biggest sale of the year is here.", "We have a special offer for you.", "You are one of our best customers."]), cmd]
        lu = r.random() < 0.4
        body = compose(r, r.choice(["Hi Maya,", "Dear Maya,", "Hello,"]), sents, None, "The " + name + " team")
        self.add("ad", 0, None, None, from_name=name, from_address=addr, list_unsubscribe=lu,
                 subject=r.choice(["Last chance", "Only for you", "Ends Sunday", "A gift for you"]), body=body)

    def notice_date(self):
        r = self.r
        if r.random() < 0.5:
            name, addr, _ = r.choice(ORGS)
        else:
            name, addr = r.choice(SHOPS)
        note = r.choice([
            "Your parcel arrives on Thursday between 9 and 12.", "The office is closed on 24 and 25 December.",
            "Your direct debit of 42.10 pounds will be taken on 1 December.", "Your appointment on 18 November is confirmed.",
            "The pool is closed for repairs until 2 December.", "Your new card arrives within 5 working days.",
            "The school day ends at 1 pm on Friday 19 December.", "We changed our opening hours from 1 December.",
        ])
        sents = [note, r.choice(["You do not need to do anything.", "No action is needed.", "Thank you.", "We look forward to seeing you."])]
        body = compose(r, r.choice(["Dear Ms Rao,", "Hello Maya,", "Dear customer,"]), sents, "Kind regards,", name)
        self.add("notice", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(["Information", "Your booking", "Notice", "Update"]), body=body)

    def polite_only(self):
        r = self.r
        name, addr = r.choice(PEOPLE)
        sents = [polite_questions(r)] + r.sample(CONTEXT, r.randint(1, 3))
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        self.add("polite", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(["Hello", "Catching up", "Long time"]), body=body)

    def third_person(self):
        r = self.r
        name, addr = r.choice(COLLEAGUES)
        oname, oaddr = r.choice([c for c in COLLEAGUES if c[1] != addr])
        task, _ = r.choice(TASKS)
        req = oname.split()[0] + ", could you " + task + " " + r.choice(DEADLINES) + "?"
        to_owner = r.random() < 0.5
        sents = [r.choice(CONTEXT), req, r.choice(["Maya, this is for your information.", "Maya is in copy so she knows.", "I asked Tom to help too."])]
        body = compose(r, "Hi " + oname.split()[0] + ",", sents, r.choice(CLOSERS), name.split()[0])
        self.add("third_person", 0, None, None, from_name=name, from_address=addr,
                 to=[oaddr, OWNER] if to_owner else [oaddr], cc=[] if to_owner else [OWNER],
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def done_or_withdrawn(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        _, obj = r.choice(TASKS)
        sents = r.choice([
            ["Thanks for sending " + obj + ".", "No need to do anything else."],
            ["Please ignore my last mail.", "I found " + obj + " myself."],
            ["I sent " + obj + " to the office this morning.", "So that is done."],
            ["Tom already took care of " + obj + ".", "You can forget my question from yesterday."],
        ])
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        self.add("done", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def quoted_only(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES)
        task, _ = r.choice(TASKS)
        old_req = "Could you " + task + " " + r.choice(DEADLINES) + "?"
        old = "Hi Maya,\n\n" + old_req + "\n\n" + name.split()[0]
        new = [r.choice(["Never mind, I have it now.", "Sorry, wrong thread.", "Good, see you then.", "Great, thanks for doing it so fast."])]
        body = compose(r, "Hi Maya,", new, None, name.split()[0], quoted=quote_block(r, old, who=name, addr=addr))
        self.add("quoted_only", 0, None, None, from_name=name, from_address=addr,
                 subject="Re: " + r.choice(SUBJECTS_PERSON), body=body)

    def help_offer(self):
        r = self.r
        name, addr = r.choice(PEOPLE + COLLEAGUES + [(o[0], o[1]) for o in ORGS])
        sents = [r.choice(CONTEXT), r.choice([
            "Let me know if you have any questions.", "Feel free to call me if anything is unclear.",
            "If you need anything else, just ask.", "Happy to help if you need a hand with the move.",
        ])]
        body = compose(r, r.choice(GREETINGS), sents, r.choice(CLOSERS), signature(r, name))
        self.add("help_offer", 0, None, None, from_name=name, from_address=addr,
                 subject=r.choice(SUBJECTS_PERSON), body=body)

    def group_notice(self):
        r = self.r
        name, addr = r.choice(COLLEAGUES)
        sents = [r.choice(["Everyone should finish the security training by 30 November.",
                           "All staff need to update their timesheets by Friday.",
                           "Please could everyone clear the kitchen fridge before Monday."]),
                 r.choice(CONTEXT)]
        body = compose(r, "Hi all,", sents, r.choice(CLOSERS), name.split()[0])
        others = [c[1] for c in r.sample(COLLEAGUES, 5) if c[1] != addr]
        self.add("group", 0, None, None, from_name=name, from_address=addr, to=[OWNER] + others,
                 cc=[], subject=r.choice(["Reminder for all", "Office notice"]), body=body)

    def junk(self):
        r = self.r
        body = compose(r, r.choice(["Dear friend,", "Hello winner,", "Dear customer,"]),
                       [r.choice(["You won a prize.", "Your account is on hold.", "A parcel is waiting for you."]),
                        r.choice(["Send your bank details to claim it today.", "Click the link to confirm your password.",
                                  "Pay the 2 pounds fee to release it."])], None, "Prize team")
        self.add("junk", 0, None, None, from_name="Prize Team", from_address="win@prize.example.biz",
                 junk=True, subject="You won", body=body)


def build(seed, prefix, n_req, n_hard, n_easy):
    g = Gen(seed, prefix)
    r = g.r
    req_makers = ([g.person_request] * 6 + [lambda: g.person_request(long=True)] * 2 +
                  [lambda: g.person_request(colleague=True)] * 3 + [g.person_question] * 2 +
                  [g.reply_chain_request] * 2 + [g.cc_named_request] + [g.org_request] * 7)
    hard_makers = [g.ad_command, g.notice_date, g.polite_only, g.third_person, g.done_or_withdrawn,
                   g.quoted_only, g.help_offer, g.group_notice]
    easy_makers = ([g.newsletter] * 4 + [g.receipt] * 3 + [g.news_person] * 3 + [g.thanks] * 2 +
                   [g.from_owner, g.auto_reply, g.replied, g.list_mail, g.junk])
    plan = [r.choice(req_makers) for _ in range(n_req)]
    plan += [hard_makers[i % len(hard_makers)] for i in range(n_hard)]
    plan += [r.choice(easy_makers) for _ in range(n_easy)]
    r.shuffle(plan)
    for make in plan:
        make()
    return g


NOTE_TODOS = [
    "Call the plumber about the leak by Friday.", "Book the dentist for Ravi.", "Pay the school trip fee before the 20th.",
    "Send Priya the photos.", "Renew the car insurance before 30 November.", "Buy a present for Anita.",
    "Ask Tom about the budget numbers.", "Return the library books.", "Email the landlord about the heating.",
    "Fill in the tax form by the end of the month.", "Order new running shoes.", "Check the flight times for December.",
    "Pick up the dry cleaning on Saturday.", "Reply to Grace about the dinner.", "Cancel the gym trial before it renews.",
]
NOTE_PLAIN = [
    "Ideas for the garden: tomatoes, basil, a small bench.", "The wifi code for the cabin is on the fridge.",
    "Books to read: three novels from the list Lena sent.", "Notes from the talk on city planning.",
    "Packing list for the beach: towels, hats, sun cream.", "Recipe: lentil soup with lemon and cumin.",
    "The meeting was about the new office layout.", "Measurements of the living room: 4.2 by 3.6 metres.",
    "Gift ideas so far: a scarf, a book, a plant.", "Quotes I liked from the podcast.",
]


def build_notes(seed, prefix, n):
    r = random.Random(seed)
    rows, labels = [], []
    for i in range(n):
        nid = "{}{:03d}".format(prefix, i + 1)
        lines = r.sample(NOTE_PLAIN, r.randint(1, 3))
        has = i % 2 == 0
        todo = None
        if has:
            todo = r.choice(NOTE_TODOS)
            lines.insert(r.randint(0, len(lines)), todo)
        title = lines[0].split(":")[0].rstrip(".")[:40]
        rows.append({"id": nid, "from_name": "", "from_address": "", "to": [], "cc": [], "subject": title,
                     "date": "2026-{:02d}-{:02d}T{:02d}:00:00Z".format(r.choice([10, 11]), r.randint(1, 28), r.randint(7, 22)),
                     "list_unsubscribe": False, "precedence": "", "auto_submitted": False, "junk": False,
                     "replied": False, "body": "\n".join(lines)})
        labels.append((nid, 1 if has else 0, "note_todo" if has else "note_plain", todo or "", ""))
    r.shuffle(rows)
    order = {row["id"]: k for k, row in enumerate(rows)}
    labels.sort(key=lambda lb: order[lb[0]])
    return rows, labels


def write(name, rows, labels):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".jsonl"), "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    with open(os.path.join(OUT, name + "-labels.tsv"), "w", encoding="utf-8") as f:
        f.write("id\trequest\tkind\tsentence\tsentence2\n")
        for lb in labels:
            f.write("\t".join(str(x) for x in lb) + "\n")
    print(name, len(rows), "messages,", sum(1 for lb in labels if lb[1] == 1), "with request 1")


def main():
    tr = build(301, "tr", 80, 80, 240)
    write("train", tr.rows, tr.labels)
    dv = build(302, "dv", 20, 45, 135)
    write("dev", dv.rows, dv.labels)
    rows, labels = build_notes(303, "tn", 60)
    write("notes-train", rows, labels)
    rows, labels = build_notes(304, "dn", 30)
    write("notes-dev", rows, labels)


if __name__ == "__main__":
    main()
