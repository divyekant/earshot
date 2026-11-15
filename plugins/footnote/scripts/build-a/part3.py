# Flags v2, build-a, part 3: hard messages with no request (done or taken back, own request in a quote, help offers).
# Each message is written by hand, one by one.
from part1 import add, M

# Done or taken back.
add("b091", "Joe Varga", "joe.varga@example.net", "Re: Saturday", "2026-11-04T09:00:00Z",
    "Hi Maya,\n\nForget my mail about the walk, it's going to rain all day. We'll try next month.\n\nJoe", 0, "done")
add("b092", "Tomasz Wolak", "t.wolak@example.com", "Re: budget sheet", "2026-11-05T08:00:00Z",
    "Maya,\n\nGot it, thanks. The sheet is closed now.\n\nTomasz", 0, "done")
add("b093", "Nina Holt", "nina.holt@example.net", "re: lift?", "2026-11-05T07:30:00Z",
    "no need for the lift anymore, my brother is taking me. thanks anyway!\n\nn", 0, "done")
add("b094", "Lena Fischer", "lena.fischer@example.org", "Re: Monday", "2026-11-07T10:00:00Z",
    "Hi Maya,\n\nI found the summary on the shared drive, so you don't have to send it. All set for Monday.\n\nLena", 0, "done")
add("b095", "Ravi Patel", "ravi.patel@example.com", "van - sorted", "2026-11-08T12:00:00Z",
    "Hey,\n\nI booked the van with Noah's card in the end, so nothing from your side. See you on the 14th.\n\nRavi", 0, "done")
add("b096", "Ade Okonjo", "ade.okonjo@example.com", "Re: photos from the wedding", "2026-11-09T09:30:00Z",
    "Maya,\n\nRosa already chose the photos, sorry! You do not need to do anything. The album will be lovely.\n\nAde", 0, "done")
add("b097", "Harbour Dental", "reception@harbourdental.example.com", "Appointment confirmed", "2026-11-10T09:00:00Z",
    "Dear Ms Rao,\n\nThank you for confirming your check-up on 18 November at 10:20. We look forward to seeing you.\n\nHarbour Dental", 0, "done")
add("b098", "Paul Evans", "paul.evans@example.com", "Re: slides", "2026-11-06T16:00:00Z",
    "Maya,\n\nAs agreed, I fixed the last slides myself. Thanks for the notes earlier.\n\nPaul", 0, "done")
add("b099", "Mum", "anita.rao@example.com", "Re: Sunday", "2026-11-09T10:00:00Z",
    "Maya love,\n\nI ordered a new dish, so don't bring yours. Ring me when you can, but there's no rush.\n\nMum", 0, "done")
add("b100", "Ben Ortiz", "ben.ortiz@example.net", "Re: draft", "2026-11-09T11:00:00Z",
    "Hi Maya,\n\nAna got the final version from the drive, so all good. Thanks!\n\nBen", 0, "done")
add("b101", "Omar Haddad", "omar.haddad@example.org", "Re: Re: plumber", "2026-11-10T08:00:00Z",
    "Maya,\n\nThe plumber chose Thursday himself, so I told him yes. Nothing to do.\n\nOmar", 0, "done")
add("b102", "Grace Kim", "grace.kim@example.net", "Re: dinner", "2026-11-08T12:00:00Z",
    "Hi Maya,\n\nBen saw you at the market and you said yes, so I counted you in. Table for 8 is booked!\n\nGrace", 0, "done")
add("b103", "Sam Lee", "sam.lee@example.net", "Re: form", "2026-11-17T09:00:00Z",
    "Hi Maya,\n\nGot your signed form this morning, you're on the team list now.\n\nSam", 0, "done")
add("b104", "Westfield Council Tax", "counciltax@westfield.example.gov", "Payment received", "2026-11-20T07:30:00Z",
    "Dear Maya Rao,\n\nAccount reference CT-448812. We received your payment of 142.00 pounds. There is nothing more to pay this year.\n\nWestfield Council", 0, "done")
add("b105", "Jo Turner", "jo.turner@example.net", "Re: the cat", "2026-11-12T18:00:00Z",
    "Maya, change of plan - we're not going away after all, so Pepper is fine. Thank you for saying yes though!\n\nJo", 0, "done")

# The owner's own request, only in quoted old text.
add("b106", "Will Grant", "will.grant@example.com", "Re: the pitch", "2026-11-04T15:00:00Z",
    "Hi Maya,\n\nDone, the three copies are on the front desk.\n\nWill\n\nOn 4 Nov, Maya Rao wrote:\n> Can you print three copies before 2pm and leave them at the front desk?", 0, "quoted")
add("b107", "Kofi Mensah", "kofi.mensah@example.net", "Re: club dates", "2026-11-05T19:00:00Z",
    "Thanks Maya, I put the dates in the club calendar.\n\nKofi\n\n> Could you add the three match dates to the calendar by Friday?\n> Maya", 0, "quoted")
add("b108", "Anna Novak", "anna.novak@example.org", "Re: invoice 2207", "2026-11-06T09:00:00Z",
    "Dear Maya,\n\nYes, finance paid it today.\n\nAnna\n\nOn Wed, 4 Nov, Maya Rao wrote:\n> Please tell me when finance pays invoice 2207.\n> Thanks, Maya", 0, "quoted")
add("b109", "Tom Hale", "tom.hale@example.com", "Re: start date", "2026-11-07T07:00:00Z",
    "Monday 8am works for me.\n\nTom\n\nOn 6 Nov 2026, at 20:11, Maya Rao <maya.rao@example.com> wrote:\n> Can you start on Monday? Please tell me by Saturday.", 0, "quoted")
add("b110", "Priya Shah", "priya.shah@example.com", "Re: hotel", "2026-11-08T21:00:00Z",
    "Booked it!! Two rooms, near the river.\n\nP\n\nMaya Rao wrote:\n> Would you book the hotel tonight? I will pay you back.", 0, "quoted")
add("b111", "Sofia Marin", "sofia.marin@example.org", "Re: the lease", "2026-11-09T10:00:00Z",
    "Dear Maya,\n\nThe parking space is in the lease now, clause 4.\n\nKind regards,\nSofia\n\nOn 8 Nov, Maya Rao wrote:\n> Can you please add the parking space before I sign?", 0, "quoted")
add("b112", "Hana Sato", "hana.sato@example.org", "Re: Re: book club", "2026-11-13T09:00:00Z",
    "Lovely choice, I told the others.\n\nHana\n\n> Please send the title to the group by Friday.\n> I chose 'The Salt Path'.", 0, "quoted")
add("b113", "Martin Leclerc", "martin.leclerc@example.com", "Re: clause 7", "2026-11-13T14:00:00Z",
    "Maya,\n\nLegal agrees with your view. We can sign.\n\nMartin\n\n-----Original Message-----\nFrom: Maya Rao\nCould you check with legal and tell me by Thursday?", 0, "quoted")
add("b114", "Dad", "vik.rao@example.com", "Re: car", "2026-11-21T08:00:00Z",
    "Booked it for you on the 1st at 9. You owe me a coffee.\n\nDad\n\nOn 20 Nov, Maya Rao wrote:\n> Dad, can you book the MOT for me? I'm swamped.", 0, "quoted")
add("b115", "Julia Costa", "julia.costa@example.org", "Re: headcount", "2026-11-18T08:00:00Z",
    "Hi Maya,\n\nThe team leads sent me their numbers, all in the sheet now.\n\nJulia\n\nOn Tue, 17 Nov, Maya Rao wrote:\n> Julia, please ask the team leads for their headcount by Wednesday.", 0, "quoted")

# Help offers and polite closings.
add("b116", "Fenwick HR", "hr@fenwick.example.com", "Welcome pack", "2026-11-11T12:00:00Z",
    "Dear Maya,\n\nThank you for uploading your documents. Your welcome pack is attached. If you have any questions, let us know.\n\nFenwick HR", 0, "offer")
add("b117", "Tom Hale", "tom.hale@example.com", "tiles", "2026-11-16T18:00:00Z",
    "Maya, the wall is done. If any tile sounds hollow, give me a call and I'll come back.\n\nTom", 0, "offer")
add("b118", "Greenline Energy", "accounts@greenline.example.com", "Meter reading received", "2026-11-19T08:00:00Z",
    "Dear Maya Rao,\n\nThank you for your reading. Your next bill uses it. If anything looks wrong, call us on 0800 496 0300.\n\nGreenline Energy", 0, "offer")
add("b119", "Mei Tanaka", "mei.tanaka@example.org", "leaflet", "2026-11-20T10:00:00Z",
    "Dear Maya,\n\nThe leaflet went to print. Thank you so much for your help. Let me know if I can ever help you with a Japanese text.\n\nMei", 0, "offer")
add("b120", "Noah Brooks", "noah.brooks@example.com", "boxes", "2026-11-30T12:00:00Z",
    "Hey Maya,\n\nBoxes are out of your garage, thanks a million. If you ever need a hand with anything, just shout.\n\nNoah", 0, "offer")
add("b121", "Daniel Brandt", "d.brandt@example.com", "Re: reference", "2026-11-19T09:00:00Z",
    "Hello Maya,\n\nThey got your reference and I have the job! Feel free to call me if you want the details.\n\nDaniel", 0, "offer")
add("b122", "Lumen Home", "orders@lumenhome.example.com", "Delivery booked", "2026-11-20T08:00:00Z",
    "Hello Maya,\n\nYour sofa comes on 2 December between 8 and 12. If you need to change the day, you can do it on our site.\n\nLumen Home", 0, "offer")
add("b123", "Irene Castell", "irene.castell@example.org", "thank you", "2026-11-05T09:00:00Z",
    "Maya,\n\nGot the keys, thank you! Let me know if you want to borrow the ladder this weekend.\n\nIrene", 0, "offer")
add("b124", "Halden Bank", "letters@haldenbank.example.com", "Address confirmed", "2026-11-18T08:00:00Z",
    "Dear Ms Rao,\n\nThank you, your address is confirmed. If you have questions about your account, our team is here to help.\n\nHalden Bank", 0, "offer")
add("b125", "Chiara Russo", "chiara.russo@example.org", "back at work", "2026-11-17T09:00:00Z",
    "Hi Maya,\n\nI'm back, thank you for covering Thursday. Happy to help if you need anything for your meeting next week.\n\nChiara", 0, "offer")
add("b126", "Rosa Diaz", "rosa.diaz@example.net", "Re: Christmas", "2026-11-15T10:00:00Z",
    "Maya,\n\nGreat, Christmas is at yours then! If you want me to bring chairs, just say.\n\nRosa", 0, "offer")
add("b127", "Mehta Surgery", "appointments@mehtasurgery.example.nhs.uk", "Test results", "2026-11-26T08:00:00Z",
    "Dear Maya Rao,\n\nYour blood test results are normal. Dr Mehta will talk you through them on 4 December. If you have questions before then, call the surgery.\n\nMehta Surgery", 0, "offer")
add("b128", "Ali Reed", "ali.reed@example.net", "hedge", "2026-11-20T17:00:00Z",
    "Maya,\n\nHedge looks great. I paid the man for both sides, my treat this time. Shout if you ever need the ladder.\n\nAli", 0, "offer")
add("b129", "Kofi Mensah", "kofi.mensah@example.net", "minutes sent", "2026-11-12T08:00:00Z",
    "Hi Maya,\n\nThanks for the notes, the minutes went out last night. If you spot a mistake, tell me and I'll fix it.\n\nKofi", 0, "offer")
add("b130", "Elm Park Primary", "office@elmpark.example.sch.uk", "Trip payment received", "2026-11-20T08:15:00Z",
    "Dear Parent,\n\nWe have received the form and the payment for Leo. If you have questions about the trip, please contact the school office.\n\nElm Park Primary School", 0, "offer")
