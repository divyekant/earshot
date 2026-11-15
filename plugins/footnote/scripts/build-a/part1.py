# Flags v2, build-a, part 1: 45 messages with a request. Each message is written by hand, one by one.
# Fields: id, from_name, from_address, to, cc, subject, date, list, precedence, auto, junk, replied, body, request, kind, sentence, sentence2
M = "maya.rao@example.com"
R = []
def add(i, fn, fa, subj, date, body, req, kind, s1="", s2="", to=None, cc=None, lst=False, prec="", auto=False, junk=False, replied=False):
    R.append(dict(id=i, from_name=fn, from_address=fa, to=to if to is not None else [M], cc=cc or [], subject=subj,
                  date=date, list_unsubscribe=lst, precedence=prec, auto_submitted=auto, junk=junk, replied=replied,
                  body=body, request=req, kind=kind, sentence=s1, sentence2=s2))

add("b001", "Joe Varga", "joe.varga@example.net", "Saturday", "2026-11-03T08:12:00Z",
    "Hi Maya,\n\nAre you still up for the walk on Saturday? I need to know by Thursday so I can book the bus.\n\nJoe",
    1, "person", "I need to know by Thursday so I can book the bus.", "Are you still up for the walk on Saturday?")
add("b002", "Irene Castell", "irene.castell@example.org", "keys", "2026-11-03T19:40:00Z",
    "Maya,\n\nI left my spare keys at yours last week. Could you drop them in my letterbox when you pass?\n\nThanks a lot,\nIrene",
    1, "person", "Could you drop them in my letterbox when you pass?")
add("b003", "Harbour Dental", "reception@harbourdental.example.com", "Your appointment on 18 November", "2026-11-04T09:00:00Z",
    "Dear Ms Rao,\n\nYou have a check-up with Dr Okafor on 18 November at 10:20. Please confirm or move the appointment by 15 November. If we do not hear from you, we will give the slot to another patient.\n\nHarbour Dental",
    1, "duty", "Please confirm or move the appointment by 15 November.")
add("b004", "Tomasz Wolak", "t.wolak@example.com", "Re: budget sheet", "2026-11-04T11:05:00Z",
    "Hi Maya,\n\nI still do not have your numbers for the travel line. Without them I cannot close the sheet.\n\nTomasz\n\nOn Mon, 2 Nov, Maya Rao wrote:\n> I will send the travel numbers this week.",
    1, "work", "I still do not have your numbers for the travel line.")
add("b005", "Nina Holt", "nina.holt@example.net", "lift?", "2026-11-04T17:22:00Z",
    "hey, any chance you could give me a lift to the station on friday morning? my train is at 7:10\n\nn",
    1, "person", "hey, any chance you could give me a lift to the station on friday morning?")
add("b006", "Westfield Council Tax", "counciltax@westfield.example.gov", "Council tax: second payment due", "2026-11-05T07:30:00Z",
    "Dear Maya Rao,\n\nAccount reference CT-448812.\n\nThe second payment of 142.00 pounds for your council tax is due on 1 December. Please pay by that date to avoid a reminder fee.\n\nWestfield Council",
    1, "duty", "Please pay by that date to avoid a reminder fee.", "The second payment of 142.00 pounds for your council tax is due on 1 December.")
add("b007", "Ade Okonjo", "ade.okonjo@example.com", "photos from the wedding", "2026-11-05T20:15:00Z",
    "Hi Maya!\n\nWe finally got the photos back. Can you pick the five you like most for the album? Rosa wants to order it next week.\n\nLove,\nAde",
    1, "person", "Can you pick the five you like most for the album?")
add("b008", "Lena Fischer", "lena.fischer@example.org", "Monday", "2026-11-06T08:45:00Z",
    "Morning Maya,\n\nThe client moved the call to Monday at 9. It would help if you could send me the summary of last quarter before then.\n\nLena",
    1, "work", "It would help if you could send me the summary of last quarter before then.")
add("b009", "Northside Library", "loans@northsidelibrary.example.org", "Items due soon", "2026-11-06T06:00:00Z",
    "Dear Maya Rao,\n\nCard 2201 4456. Two items on your card are due on 13 November: 'The Salt Path' and 'Bread at Home'. Return or renew them by that date.\n\nNorthside Library",
    1, "duty", "Return or renew them by that date.")
add("b010", "Paul Evans", "paul.evans@example.com", "slides", "2026-11-06T10:10:00Z",
    "Maya,\n\nWould you be able to look over the last three slides today? The deck goes to print at five.\n\nPaul",
    1, "work", "Would you be able to look over the last three slides today?")
add("b011", "Grace Kim", "grace.kim@example.net", "dinner", "2026-11-06T18:02:00Z",
    "Hi Maya,\n\nWe are doing dinner for Ben's birthday on the 21st. Tell me by Sunday if you can come, so I can book the table.\n\nxx Grace",
    1, "person", "Tell me by Sunday if you can come, so I can book the table.")
add("b012", "Orbit Parcel", "notify@orbitparcel.example.com", "Your parcel is waiting", "2026-11-07T12:00:00Z",
    "Hello Maya,\n\nParcel OP-77120 from Lumen Home is at the Station Road shop. Collect your parcel by 21 November. After that date it goes back to the sender.\n\nOrbit Parcel",
    1, "duty", "Collect your parcel by 21 November.")
add("b013", "Ravi Patel", "ravi.patel@example.com", "van", "2026-11-07T09:30:00Z",
    "Morning,\n\nThe van is booked for the 14th. I need your ok on the price before I pay the deposit tomorrow - it's 85 for the day.\n\nRavi",
    1, "person", "I need your ok on the price before I pay the deposit tomorrow - it's 85 for the day.")
add("b014", "Sofia Marin", "sofia.marin@example.org", "the lease", "2026-11-07T16:44:00Z",
    "Dear Maya,\n\nThe new lease is ready. Please sign both copies and send one back to me before the end of the month.\n\nKind regards,\nSofia Marin\nMarin Lettings",
    1, "duty", "Please sign both copies and send one back to me before the end of the month.")
add("b015", "Ben Ortiz", "ben.ortiz@example.net", "draft", "2026-11-08T13:20:00Z",
    "Hi Maya,\n\nThanks for the draft. One thing: when can you send the final version? Ana wants to read it on the train.\n\nBen",
    1, "work", "when can you send the final version?", "One thing: when can you send the final version?")
add("b016", "Clarke Insurance", "policies@clarkeinsurance.example.com", "Your home policy renews on 1 December", "2026-11-08T07:00:00Z",
    "Dear Ms Rao,\n\nPolicy HM-30219 renews on 1 December. Please check the details below and tell us of any change by 24 November. If nothing changed, you do not need to do anything.\n\nClarke Insurance",
    1, "duty", "Please check the details below and tell us of any change by 24 November.")
add("b017", "Mum", "anita.rao@example.com", "Sunday", "2026-11-08T19:55:00Z",
    "Maya love,\n\nCan you bring the big dish on Sunday? Mine has a crack. And ring me tomorrow, I want to ask you something about Christmas.\n\nMum",
    1, "person", "Can you bring the big dish on Sunday?", "And ring me tomorrow, I want to ask you something about Christmas.")
add("b018", "Elm Park Primary", "office@elmpark.example.sch.uk", "Year 3 trip: form and payment", "2026-11-09T08:15:00Z",
    "Dear Parent,\n\nYear 3 visit the science museum on 2 December. Please return the signed consent form for Leo and pay the 12 pounds on the school app by 25 November.\n\nElm Park Primary School",
    1, "duty", "Please return the signed consent form for Leo and pay the 12 pounds on the school app by 25 November.")
add("b019", "Daniel Brandt", "d.brandt@example.com", "reference", "2026-11-09T10:01:00Z",
    "Hello Maya,\n\nI am applying for the post at Fenwick. You know my work best - would you write a short reference? They need it by the 20th.\n\nBest,\nDaniel",
    1, "person", "You know my work best - would you write a short reference?", "They need it by the 20th.")
add("b020", "Omar Haddad", "omar.haddad@example.org", "Re: plumber", "2026-11-09T14:33:00Z",
    "Maya,\n\nThe plumber can come Tuesday or Thursday. Which day suits you? I have to tell him tonight.\n\nOmar",
    1, "person", "Which day suits you?")
add("b021", "Kofi Mensah", "kofi.mensah@example.net", "minutes", "2026-11-10T09:12:00Z",
    "Hi Maya,\n\nYou took the notes at the club meeting. Could you share them with me this week? I have to send the minutes to the members.\n\nThanks,\nKofi",
    1, "person", "Could you share them with me this week?")
add("b022", "Fenwick HR", "hr@fenwick.example.com", "Documents for your start", "2026-11-10T11:00:00Z",
    "Dear Maya Rao,\n\nWelcome to Fenwick. Before your first day on 1 December, we need a copy of your passport and your bank details. Please upload them on the staff page by 24 November.\n\nFenwick HR",
    1, "duty", "Please upload them on the staff page by 24 November.", "Before your first day on 1 December, we need a copy of your passport and your bank details.")
add("b023", "Priya Shah", "priya.shah@example.com", "Re: Lisbon", "2026-11-10T21:30:00Z",
    "Maya!\n\nFlights went up again. If we want the cheap ones we have to book this week. Are you in or out? Just say yes or no.\n\nP",
    1, "person", "Are you in or out?")
add("b024", "Anna Novak", "anna.novak@example.org", "invoice 2207", "2026-11-11T08:40:00Z",
    "Dear Maya,\n\nIt still needs your signature before finance can pay it. The form is attached.\n\nRegards,\nAnna Novak",
    1, "work", "It still needs your signature before finance can pay it.")
add("b025", "Riverside Water", "billing@riversidewater.example.com", "Bill 99120 - amount due", "2026-11-11T06:30:00Z",
    "Dear customer,\n\nAccount 55031-7 (Maya Rao). Your bill of 61.40 pounds is due on 28 November. Please pay it by direct debit or on our site before that date.\n\nRiverside Water",
    1, "duty", "Please pay it by direct debit or on our site before that date.", "Your bill of 61.40 pounds is due on 28 November.")
add("b026", "Jo Turner", "jo.turner@example.net", "the cat", "2026-11-11T17:05:00Z",
    "Hi Maya,\n\nWe are away from Friday to Monday. Would you feed Pepper on Saturday and Sunday? The key is under the blue pot.\n\nThank you!!\nJo",
    1, "person", "Would you feed Pepper on Saturday and Sunday?")
add("b027", "Martin Leclerc", "martin.leclerc@example.com", "contract", "2026-11-12T09:00:00Z",
    "Maya,\n\nLegal is waiting on us. Please read clause 7 and give me your view by tomorrow noon.\n\nMartin",
    1, "work", "Please read clause 7 and give me your view by tomorrow noon.")
add("b028", "Hana Sato", "hana.sato@example.org", "book club", "2026-11-12T12:12:00Z",
    "Hello Maya,\n\nIt is your turn to choose the book for January. Let me know the title before the meeting on the 3rd so people have time to get it.\n\nHana",
    1, "person", "Let me know the title before the meeting on the 3rd so people have time to get it.")
add("b029", "Dr Mehta's Surgery", "appointments@mehtasurgery.example.nhs.uk", "Blood test", "2026-11-12T08:00:00Z",
    "Dear Maya Rao,\n\nDr Mehta asks you to book a blood test before your review on 4 December. Call the surgery on 0161 496 0102 to book it.\n\nMehta Surgery",
    1, "duty", "Dr Mehta asks you to book a blood test before your review on 4 December.", "Call the surgery on 0161 496 0102 to book it.")
add("b030", "Will Grant", "will.grant@example.com", "quick favour", "2026-11-13T10:25:00Z",
    "Hi Maya,\n\nQuick one. My laptop died and the files for the pitch are on the shared drive. Can you print three copies before 2pm and leave them at the front desk?\n\nWill",
    1, "work", "Can you print three copies before 2pm and leave them at the front desk?")
add("b031", "Rosa Diaz", "rosa.diaz@example.net", "Christmas", "2026-11-13T20:00:00Z",
    "Maya,\n\nWe are trying to plan the 25th. Are you able to host this year, or should we go to Tom's? I would like to tell everyone by the weekend.\n\nRosa",
    1, "person", "Are you able to host this year, or should we go to Tom's?")
add("b032", "Greenline Energy", "accounts@greenline.example.com", "Meter reading needed", "2026-11-14T07:15:00Z",
    "Dear Maya Rao,\n\nAccount GL-210088. We need a meter reading for your gas meter. Send us the reading by 20 November, or we will estimate your next bill.\n\nGreenline Energy",
    1, "duty", "Send us the reading by 20 November, or we will estimate your next bill.", "We need a meter reading for your gas meter.")
add("b033", "Leo's teacher", "j.marsh@elmpark.example.sch.uk", "Leo's reading book", "2026-11-14T15:30:00Z",
    "Dear Ms Rao,\n\nLeo has not brought his reading book back for two weeks. Could you look for it at home and send it in on Monday?\n\nMany thanks,\nJenny Marsh",
    1, "person", "Could you look for it at home and send it in on Monday?")
add("b034", "Tom Hale", "tom.hale@example.com", "tiles", "2026-11-15T08:05:00Z",
    "Maya, the tiles came in two colours. Do you want the grey or the sand? I start on the wall Tuesday so I need to know Monday.\n\nTom",
    1, "person", "Do you want the grey or the sand?", "I start on the wall Tuesday so I need to know Monday.")
add("b035", "Chiara Russo", "chiara.russo@example.org", "Fwd: room booking", "2026-11-15T11:11:00Z",
    "Maya, see below. Can you book the small room for Thursday? I am off sick.\n\nChiara\n\n---------- Forwarded message ---------\nFrom: Facilities\nThe rooms for next week are open for booking.",
    1, "work", "Can you book the small room for Thursday?")
add("b036", "Sam Lee", "sam.lee@example.net", "form", "2026-11-16T09:50:00Z",
    "Hi Maya,\n\nI need the signed form from you before the 20th, or the club cannot add you to the team list.\n\nSam",
    1, "person", "I need the signed form from you before the 20th, or the club cannot add you to the team list.")
add("b037", "Halden Bank", "letters@haldenbank.example.com", "Action needed on your account", "2026-11-16T08:00:00Z",
    "Dear Ms Rao,\n\nAccount ending 4410. We need to check your address again, as the law asks us to. Please confirm your address in the app within 14 days. If you do not, some payments may stop.\n\nHalden Bank",
    1, "duty", "Please confirm your address in the app within 14 days.")
add("b038", "Eve Long", "eve.long@example.com", "Sat", "2026-11-16T22:10:00Z",
    "you still have my tent from the summer?? I need it back for saturday x",
    1, "person", "I need it back for saturday x", "you still have my tent from the summer??")
add("b039", "Julia Costa", "julia.costa@example.org", "numbers for Q4", "2026-11-17T09:20:00Z",
    "Hi Maya,\n\nThe board pack closes Friday. I need the Q4 headcount from you by Wednesday end of day.\n\nThanks,\nJulia",
    1, "work", "I need the Q4 headcount from you by Wednesday end of day.")
add("b040", "Ali Reed", "ali.reed@example.net", "Re: Re: garden", "2026-11-17T18:00:00Z",
    "Maya,\n\nOk, the man can cut the hedge on our side too. Can you pay him your half when he comes on Friday? It's 40.\n\nAli\n\nOn 15 Nov, Maya Rao wrote:\n> Fine by me if he does both sides.",
    1, "person", "Can you pay him your half when he comes on Friday?")
add("b041", "Westfield Recycling", "waste@westfield.example.gov", "Your garden waste permit", "2026-11-18T07:00:00Z",
    "Dear Maya Rao,\n\nPermit GW-6620 for 14 Elm Road ends on 31 December. Renew it by 15 December to keep your collections in January.\n\nWestfield Council",
    1, "duty", "Renew it by 15 December to keep your collections in January.")
add("b042", "Noah Brooks", "noah.brooks@example.com", "help with the move", "2026-11-18T12:40:00Z",
    "Hey Maya,\n\nWe move on the 29th. Would it be ok if we left four boxes in your garage for a week? Let me know before Friday.\n\nNoah",
    1, "person", "Would it be ok if we left four boxes in your garage for a week?", "Let me know before Friday.")
add("b043", "Mei Tanaka", "mei.tanaka@example.org", "translation", "2026-11-19T10:30:00Z",
    "Dear Maya,\n\nYou offered to check the Spanish version of the leaflet. Is Thursday still possible for you? The printer needs it on Friday.\n\nThank you,\nMei",
    1, "work", "Is Thursday still possible for you?")
add("b044", "Lumen Home", "orders@lumenhome.example.com", "Order 41794: choose a delivery day", "2026-11-19T08:00:00Z",
    "Hello Maya,\n\nYour sofa (order 41794) is ready. Choose a delivery day on our site by 26 November. If you do not choose, we will store it for 14 days and then charge a fee.\n\nLumen Home",
    1, "duty", "Choose a delivery day on our site by 26 November.")
add("b045", "Dad", "vik.rao@example.com", "car", "2026-11-20T08:15:00Z",
    "Maya,\n\nThe MOT on your car is due on 2 December. Do not forget to book it, the garage gets busy before Christmas.\n\nDad",
    1, "person", "Do not forget to book it, the garage gets busy before Christmas.", "The MOT on your car is due on 2 December.")
