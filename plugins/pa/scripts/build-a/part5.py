# Flags v2, build-a, part 5: 100 plain messages with no request (news, chat, thanks, receipts, notices).
# Each message is written by hand, one by one. Some have a question with no task for the owner.
from part1 import add, R, M

# News and chat from persons.
add("b201", "Joe Varga", "joe.varga@example.net", "back home", "2026-11-03T21:00:00Z",
    "Hi Maya,\n\nWe got back from Wales last night. The cottage was tiny but the views were great. Photos soon.\n\nJoe", 0, "news")
add("b202", "Irene Castell", "irene.castell@example.org", "new job", "2026-11-04T07:50:00Z",
    "Maya!\n\nI got the job at the museum. I start in January. I am so happy I could cry.\n\nIrene", 0, "news")
add("b203", "Nina Holt", "nina.holt@example.net", "lol", "2026-11-04T22:10:00Z",
    "the cat climbed into the washing basket again and fell asleep on my good shirt. no regrets apparently\n\nn", 0, "chat")
add("b204", "Ade Okonjo", "ade.okonjo@example.com", "we moved", "2026-11-05T12:00:00Z",
    "Hi Maya,\n\nJust so you know, our new address is 14 Hill Row. The old one stops working at the end of the month.\n\nAde", 0, "news")
add("b205", "Grace Kim", "grace.kim@example.net", "Ben's party", "2026-11-22T10:00:00Z",
    "Hi Maya,\n\nThank you for coming last night. Ben loved the book. The cake was a mess but nobody cared.\n\nxx Grace", 0, "thanks")
add("b206", "Mum", "anita.rao@example.com", "the garden", "2026-11-06T15:30:00Z",
    "Maya love,\n\nYour dad finished the new fence today. It looks very smart. The roses are still out, can you believe it.\n\nMum", 0, "chat")
add("b207", "Ravi Patel", "ravi.patel@example.com", "the move", "2026-11-15T19:00:00Z",
    "Hi,\n\nAll done. The van is back and the last box is in the flat. Thanks again for your help today.\n\nRavi", 0, "thanks")
add("b208", "Hana Sato", "hana.sato@example.org", "Tokyo", "2026-11-07T23:40:00Z",
    "Hello Maya,\n\nGreetings from Tokyo. It is cold but bright here. I ate too much ramen and walked 20 km.\n\nHana", 0, "news")
add("b209", "Tom Hale", "tom.hale@example.com", "match", "2026-11-08T17:45:00Z",
    "We won 3-1. Leo scored his first goal of the season. He has not stopped talking about it.\n\nTom", 0, "news")
add("b210", "Joe Varga", "joe.varga@example.net", "how are you?", "2026-11-09T09:00:00Z",
    "Hi Maya,\n\nHow are you doing? It feels like ages. Things here are calm. Work is fine and the kids are well.\n\nJoe", 0, "chat")
add("b211", "Irene Castell", "irene.castell@example.org", "the keys", "2026-11-05T20:30:00Z",
    "Got the keys, thank you! You are a star.\n\nIrene", 0, "thanks")
add("b212", "Priya Shah", "priya.shah@example.com", "baby news", "2026-11-10T06:15:00Z",
    "Dear Maya,\n\nOur little girl Asha was born on Sunday at 4:12 in the morning. She and I are both well and very tired.\n\nLove,\nPriya", 0, "news")
add("b213", "Nina Holt", "nina.holt@example.net", "friday", "2026-11-07T08:20:00Z",
    "made the train with a minute to spare. thank you so much for the lift!!\n\nn", 0, "thanks")
add("b214", "Ade Okonjo", "ade.okonjo@example.com", "album", "2026-11-12T19:00:00Z",
    "Hi Maya,\n\nThank you for picking the photos. Rosa ordered the album today. It should come in two weeks.\n\nAde", 0, "thanks")
add("b215", "Sam Lee", "sam.lee@example.net", "funny", "2026-11-11T13:00:00Z",
    "Saw this sign in the park today: 'Please do not feed the ducks bread, they prefer peas.' Who knew.\n\nSam", 0, "chat")
add("b216", "Mum", "anita.rao@example.com", "Christmas", "2026-11-09T20:10:00Z",
    "Maya love,\n\nGood talk today. So it is settled: we all come to you on the 25th and I will bring the pudding.\n\nMum", 0, "chat")
add("b217", "Hana Sato", "hana.sato@example.org", "home", "2026-11-16T12:00:00Z",
    "Back in London. Jet lag is bad. I brought you some green tea, I will give it to you next time.\n\nHana", 0, "news")
add("b218", "Lucas Brandt", "lucas.brandt@example.com", "the run", "2026-11-09T11:30:00Z",
    "Hi Maya,\n\nI finished the half marathon in 1:52. My legs hurt but I am proud. Thank you for the training tips.\n\nLucas", 0, "thanks")
add("b219", "Grace Kim", "grace.kim@example.net", "did you see", "2026-11-13T21:00:00Z",
    "Did you see the moon tonight? It was huge and orange. I stood in the street like a fool for ten minutes.\n\nG", 0, "chat")
add("b220", "Tom Hale", "tom.hale@example.com", "sorry", "2026-11-14T08:00:00Z",
    "Hi Maya,\n\nSorry I missed you on Saturday. Leo had a fever. He is fine now, back at school today.\n\nTom", 0, "news")
add("b221", "Joe Varga", "joe.varga@example.net", "Saturday walk", "2026-11-08T18:30:00Z",
    "Great walk today. My boots are still wet. Same time next month, I hope.\n\nJoe", 0, "chat")
add("b222", "Priya Shah", "priya.shah@example.com", "thank you", "2026-11-18T10:00:00Z",
    "Dear Maya,\n\nThank you for the lovely blanket for Asha. She sleeps under it every afternoon.\n\nPriya", 0, "thanks")
add("b223", "Lucas Brandt", "lucas.brandt@example.com", "book", "2026-11-17T20:00:00Z",
    "I finished the book you gave me. What an ending. I did not see it coming at all.\n\nLucas", 0, "chat")
add("b224", "Irene Castell", "irene.castell@example.org", "first day", "2026-11-19T18:40:00Z",
    "Had my first look around the museum today. My desk faces the old maps room. I think I will like it there.\n\nIrene", 0, "news")
add("b225", "Sam Lee", "sam.lee@example.net", "result", "2026-11-20T16:00:00Z",
    "Hi Maya,\n\nGood news: the scan was clear. The doctor says no more checks until next year.\n\nSam", 0, "news")

# Work news and thanks, with the owner in To.
add("b226", "Lena Fischer", "lena.fischer@example.org", "Re: summary", "2026-11-09T09:30:00Z",
    "Hi Maya,\n\nThanks for the summary. The client was happy with it and the call went well.\n\nLena", 0, "thanks")
add("b227", "Paul Evans", "paul.evans@example.com", "deck", "2026-11-06T17:30:00Z",
    "Maya,\n\nThe deck went to print at five. Thank you for the quick look at the slides.\n\nPaul", 0, "thanks")
add("b228", "Tomasz Wolak", "t.wolak@example.com", "Re: budget sheet", "2026-11-06T10:00:00Z",
    "Hi Maya,\n\nGot the travel numbers. The sheet is closed now. Thanks.\n\nTomasz", 0, "thanks")
add("b229", "Ben Ortiz", "ben.ortiz@example.net", "news", "2026-11-10T09:15:00Z",
    "Hi team,\n\nAna starts as our new head of design on Monday. She comes from a small studio in Leeds.\n\nBen",
    0, "news", to=[M, "paul.evans@example.com", "lena.fischer@example.org"])
add("b230", "Fenwick Office", "office@fenwick.example.com", "Kitchen closed on Friday", "2026-11-11T08:00:00Z",
    "Hello all,\n\nThe kitchen on floor 3 is closed on Friday for cleaning. The kitchen on floor 2 stays open.\n\nOffice team",
    0, "notice", to=["all-staff@fenwick.example.com"])
add("b231", "Lena Fischer", "lena.fischer@example.org", "out next week", "2026-11-13T15:00:00Z",
    "Hi Maya,\n\nI am off from Monday to Wednesday next week. Paul covers the client calls.\n\nLena", 0, "news")
add("b232", "Paul Evans", "paul.evans@example.com", "well done", "2026-11-14T17:00:00Z",
    "Maya,\n\nThe client signed the second phase today. Your report made the difference. Well done.\n\nPaul", 0, "thanks")
add("b233", "Ana Duarte", "ana.duarte@example.com", "hello", "2026-11-16T09:00:00Z",
    "Hi Maya,\n\nI am Ana, the new head of design. I look forward to working with you. I sit near the window on floor 3.\n\nAna", 0, "news")
add("b234", "Ben Ortiz", "ben.ortiz@example.net", "Re: final version", "2026-11-09T12:00:00Z",
    "Got it, thanks. Ana read it on the train and liked it.\n\nBen", 0, "thanks")
add("b235", "Tomasz Wolak", "t.wolak@example.com", "Q4 numbers", "2026-11-20T11:00:00Z",
    "Hi all,\n\nThe Q4 numbers are in the shared folder. Travel spend came in 4% under plan.\n\nTomasz",
    0, "news", to=[M, "ben.ortiz@example.net"])
add("b236", "Martin Leclerc", "martin.leclerc@example.com", "Re: contract", "2026-11-25T10:00:00Z",
    "Dear Maya,\n\nI am back and I read your notes. All fine from our side. We sign on Thursday as planned.\n\nMartin", 0, "news")
add("b237", "Fenwick HR", "hr@fenwick.example.com", "Holiday dates", "2026-11-18T09:00:00Z",
    "Hello all,\n\nThe office is closed from 24 December to 1 January. It opens again on 2 January.\n\nHR",
    0, "notice", to=["all-staff@fenwick.example.com"])
add("b238", "Lena Fischer", "lena.fischer@example.org", "coffee?", "2026-11-19T10:30:00Z",
    "I am getting coffee from the place on the corner if you want me to bring you one, just shout.\n\nL", 0, "offer")
add("b239", "Paul Evans", "paul.evans@example.com", "FYI", "2026-11-21T14:00:00Z",
    "Maya,\n\nFYI the client moved the review to January. Nothing changes for us this month.\n\nPaul", 0, "news")
add("b240", "Ana Duarte", "ana.duarte@example.com", "thanks", "2026-11-23T16:20:00Z",
    "Thank you for showing me around today. The tour of the archive was the best part.\n\nAna", 0, "thanks")

# Receipts.
add("b241", "Lumen Home", "orders@lumenhome.example.com", "Order LH-20931 confirmed", "2026-11-03T10:00:00Z",
    "Hello Maya,\n\nThank you for your order. Order LH-20931: 1 table lamp, 34.00 pounds. Paid by card ending 4417.\n\nLumen Home", 0, "receipt")
add("b242", "Rail North", "tickets@railnorth.example.com", "Your e-ticket", "2026-11-04T19:00:00Z",
    "Your ticket for Leeds to York on 12 November is attached. Total paid: 18.40 pounds.\n\nRail North", 0, "receipt")
add("b243", "Corner Books", "shop@cornerbooks.example.co.uk", "Receipt 88120", "2026-11-05T13:10:00Z",
    "Thank you for shopping with us. 2 books, 21.98 pounds, paid in shop.\n\nCorner Books", 0, "receipt")
add("b244", "Halden Bank", "alerts@haldenbank.example.com", "Payment sent", "2026-11-06T08:00:00Z",
    "Dear Maya Rao,\n\nYour payment of 142.00 pounds to Westfield Council was sent today.\n\nHalden Bank", 0, "receipt")
add("b245", "Kiko Taxis", "receipts@kikotaxis.example.com", "Your trip on 7 November", "2026-11-07T23:30:00Z",
    "Trip from Station Road to Hill Row. 9.80 pounds. Driver: Omar. Thank you for riding with us.", 0, "receipt")
add("b246", "Pantry Market", "receipts@pantrymarket.example.com", "Your shopping receipt", "2026-11-08T11:00:00Z",
    "Thank you for shopping at Pantry Market. Total 46.12 pounds. Points earned: 46.", 0, "receipt")
add("b247", "Swift Cars", "service@swiftcars.example.com", "Invoice SC-3021 paid", "2026-12-01T16:00:00Z",
    "Dear Maya,\n\nThank you. Invoice SC-3021 for your MOT, 54.85 pounds, is paid in full.\n\nSwift Cars", 0, "receipt")
add("b248", "Streamly", "billing@streamly.example.com", "Your monthly receipt", "2026-11-10T05:00:00Z",
    "We charged 8.99 pounds to your card for November. You do not need to do anything.\n\nStreamly", 0, "receipt")
add("b249", "Harbour Dental", "reception@harbourdental.example.com", "Payment received", "2026-11-18T11:00:00Z",
    "Dear Ms Rao,\n\nWe received your payment of 26.80 pounds for today's check-up. Thank you.\n\nHarbour Dental", 0, "receipt")
add("b250", "Travelnest", "bookings@travelnest.example.com", "Booking TN-55120 confirmed", "2026-11-11T21:00:00Z",
    "Your stay in Lisbon from 4 to 7 December is confirmed. Total paid: 312.00 pounds.\n\nTravelnest", 0, "receipt")
add("b251", "Northside Library", "loans@northsidelibrary.example.org", "Items renewed", "2026-11-12T09:00:00Z",
    "Dear Maya Rao,\n\nYou renewed 2 items. The new due date is 4 December.\n\nNorthside Library", 0, "receipt")
add("b252", "Orbit Parcel", "notify@orbitparcel.example.com", "Parcel collected", "2026-11-13T17:30:00Z",
    "Parcel OP-77120 was collected from the Station Road shop today. Thank you for using Orbit Parcel.", 0, "receipt")
add("b253", "Clarke Insurance", "policies@clarkeinsurance.example.com", "Policy HM-30219 renewed", "2026-12-01T07:00:00Z",
    "Dear Ms Rao,\n\nYour home policy renewed today. Your documents are in your online account.\n\nClarke Insurance", 0, "receipt")
add("b254", "Greenline Energy", "accounts@greenline.example.com", "Payment received", "2026-11-15T08:00:00Z",
    "Thank you. We received your payment of 88.00 pounds. Your balance is now 0.00 pounds.\n\nGreenline Energy", 0, "receipt")
add("b255", "Corner Cafe", "hello@cornercafe.example.co.uk", "Your table is booked", "2026-11-16T14:00:00Z",
    "Thank you, Grace. Table for 8 on 21 November at 19:30 is booked under the name Kim.\n\nCorner Cafe",
    0, "receipt", to=["grace.kim@example.net"], cc=[M])
add("b256", "Pantry Market", "orders@pantrymarket.example.com", "Your delivery slot", "2026-11-17T12:00:00Z",
    "Your shopping comes on Thursday between 18:00 and 19:00. Order total: 63.40 pounds.\n\nPantry Market", 0, "receipt")
add("b257", "Halden Bank", "alerts@haldenbank.example.com", "Direct debit set up", "2026-11-19T09:00:00Z",
    "Dear Maya Rao,\n\nA new direct debit to Greenline Energy is now active on your account.\n\nHalden Bank", 0, "receipt")
add("b258", "Rail North", "tickets@railnorth.example.com", "Refund processed", "2026-11-20T10:00:00Z",
    "Your refund of 9.20 pounds for the late train on 12 November was paid to your card.\n\nRail North", 0, "receipt")
add("b259", "Lumen Home", "orders@lumenhome.example.com", "Order LH-21877 confirmed", "2026-11-24T20:00:00Z",
    "Hello Maya,\n\nThank you for your order. Order LH-21877: 1 sofa, 640.00 pounds. Delivery date: 2 December.\n\nLumen Home", 0, "receipt")
add("b260", "Kiko Taxis", "receipts@kikotaxis.example.com", "Your trip on 21 November", "2026-11-21T23:50:00Z",
    "Trip from Corner Cafe to Hill Row. 12.40 pounds. Thank you for riding with us.", 0, "receipt")

# Notices with no task.
add("b261", "Westfield Council", "bins@westfield.example.gov", "Bin day change", "2026-11-03T07:00:00Z",
    "Dear resident,\n\nFrom 1 December your bins are collected on Tuesday, not Monday.\n\nWestfield Council", 0, "notice")
add("b262", "Halden Bank", "alerts@haldenbank.example.com", "Your statement is ready", "2026-11-04T06:00:00Z",
    "Dear Maya Rao,\n\nYour October statement is ready in online banking.\n\nHalden Bank", 0, "notice")
add("b263", "Brightwave", "service@brightwave.example.com", "Work in your area is done", "2026-12-03T09:00:00Z",
    "The upgrade in your area is finished. Your internet now runs at full speed.\n\nBrightwave", 0, "notice")
add("b264", "Elm Park Primary", "office@elmpark.example.sch.uk", "Photos from Sports Day", "2026-11-05T15:00:00Z",
    "Dear Parent,\n\nThe photos from Sports Day are now on the school website.\n\nElm Park Primary School",
    0, "notice", to=["year3@elmpark.example.sch.uk"])
add("b265", "Mehta Surgery", "appointments@mehtasurgery.example.nhs.uk", "Your test results", "2026-11-06T12:00:00Z",
    "Dear Maya Rao,\n\nYour recent blood test results are normal. The doctor does not need to see you.\n\nMehta Surgery", 0, "notice")
add("b266", "Orbit Parcel", "notify@orbitparcel.example.com", "Your parcel is on its way", "2026-11-06T09:00:00Z",
    "Parcel OP-77120 from Lumen Home left our hub. It should arrive at the Station Road shop tomorrow.", 0, "notice")
add("b267", "Greenline Energy", "accounts@greenline.example.com", "Your meter reading", "2026-11-07T07:00:00Z",
    "Thank you for your meter reading of 18220. We used it for your November bill.\n\nGreenline Energy", 0, "notice")
add("b268", "Rail North", "service@railnorth.example.com", "Change to your train", "2026-11-11T18:00:00Z",
    "Your 08:12 train to York on 12 November now leaves from platform 4.\n\nRail North", 0, "notice")
add("b269", "Westfield Council", "parking@westfield.example.gov", "Your parking permit", "2026-11-12T08:00:00Z",
    "Dear Maya Rao,\n\nYour parking permit for zone C is valid until 30 November next year.\n\nWestfield Council", 0, "notice")
add("b270", "Fenwick IT", "it@fenwick.example.com", "Planned outage", "2026-11-13T10:00:00Z",
    "The mail server will be down on Saturday from 22:00 to 23:00 for an update. No action is needed.\n\nFenwick IT",
    0, "notice", to=["all-staff@fenwick.example.com"], auto=True)
add("b271", "Travelnest", "bookings@travelnest.example.com", "Your stay is in 3 weeks", "2026-11-13T06:00:00Z",
    "Your hotel in Lisbon is ready for you on 4 December. Check-in is from 15:00.\n\nTravelnest", 0, "notice")
add("b272", "Halden Bank", "alerts@haldenbank.example.com", "New login", "2026-11-14T19:00:00Z",
    "Dear Maya Rao,\n\nYou logged in to online banking from a new device today at 19:02. If this was you, there is nothing to do.\n\nHalden Bank", 0, "notice")
add("b273", "Northside Library", "events@northsidelibrary.example.org", "Opening hours in December", "2026-11-15T09:00:00Z",
    "Dear member,\n\nThe library closes at 16:00 on 24 December and opens again on 27 December.\n\nNorthside Library", 0, "notice")
add("b274", "Swift Cars", "service@swiftcars.example.com", "Your car is ready", "2026-12-01T14:30:00Z",
    "Dear Maya,\n\nYour car passed the MOT. It is ready in the front car park and the keys are at the desk.\n\nSwift Cars", 0, "notice")
add("b275", "Mehta Surgery", "appointments@mehtasurgery.example.nhs.uk", "Flu clinic", "2026-11-16T08:00:00Z",
    "Dear patient,\n\nThe flu clinic runs on Saturday mornings until the end of November.\n\nMehta Surgery", 0, "notice")
add("b276", "Elm Park Primary", "office@elmpark.example.sch.uk", "Term dates", "2026-11-17T12:00:00Z",
    "Dear Parent,\n\nThe spring term starts on 6 January. The term dates for next year are on the website.\n\nElm Park Primary School",
    0, "notice", to=["parents@elmpark.example.sch.uk"])
add("b277", "Streamly", "news@streamly.example.com", "New on Streamly", "2026-11-18T17:00:00Z",
    "Season 2 of The Lighthouse is now on Streamly. All episodes are out.", 0, "newsletter", lst=True)
add("b278", "Lumen Home", "orders@lumenhome.example.com", "Your sofa is on its way", "2026-12-02T07:00:00Z",
    "Hello Maya,\n\nYour sofa is on the van today. The driver will call 30 minutes before.\n\nLumen Home", 0, "notice")
add("b279", "Westfield Council", "roads@westfield.example.gov", "Road works on Hill Row", "2026-11-19T07:00:00Z",
    "Dear resident,\n\nHill Row is closed to cars on 26 and 27 November for road repairs. Walkers can still pass.\n\nWestfield Council", 0, "notice")
add("b280", "Greenline Energy", "accounts@greenline.example.com", "Your annual summary", "2026-11-20T07:00:00Z",
    "Dear Maya Rao,\n\nLast year you used 2,830 kWh of power. That is 6% less than the year before.\n\nGreenline Energy", 0, "notice")

# Hard cases: a question or an action word, but no task for the owner.
add("b281", "Joe Varga", "joe.varga@example.net", "Re: walk", "2026-11-04T09:00:00Z",
    "Great, see you Saturday then. I booked the bus already, so you do not need to do anything.\n\nJoe", 0, "done")
add("b282", "Grace Kim", "grace.kim@example.net", "Re: dinner", "2026-11-07T12:00:00Z",
    "Brilliant, you are on the list. I booked the table for 8 at 19:30.\n\nxx G", 0, "done")
add("b283", "Mum", "anita.rao@example.com", "Re: Sunday", "2026-11-09T21:00:00Z",
    "Never mind the dish, Auntie Leela lent me hers. Just bring yourselves.\n\nMum", 0, "done")
add("b284", "Nina Holt", "nina.holt@example.net", "guess what", "2026-11-12T20:00:00Z",
    "guess what?? I passed my driving test! no more lifts needed haha\n\nn", 0, "news")
add("b285", "Ravi Patel", "ravi.patel@example.com", "Re: van", "2026-11-08T08:00:00Z",
    "Thanks for the ok. I paid the deposit this morning, all sorted.\n\nRavi", 0, "done")
add("b286", "Tom Hale", "tom.hale@example.com", "did you know", "2026-11-18T19:30:00Z",
    "Did you know the old cinema on Bank Street is opening again? They had a sign up today.\n\nTom", 0, "chat")
add("b287", "Lucas Brandt", "lucas.brandt@example.com", "tips", "2026-11-19T07:00:00Z",
    "If you ever want to try a half marathon, I have a training plan I can send you. No pressure at all.\n\nLucas", 0, "offer")
add("b288", "Irene Castell", "irene.castell@example.org", "wondering", "2026-11-21T22:00:00Z",
    "I wonder if the museum café is any good. I will find out on Monday I suppose.\n\nIrene", 0, "chat")
add("b289", "Paul Evans", "paul.evans@example.com", "Re: slides", "2026-11-06T12:30:00Z",
    "No need to look at the slides after all, Lena already checked them. Thanks anyway.\n\nPaul", 0, "done")
add("b290", "Sam Lee", "sam.lee@example.net", "Re: lunch", "2026-11-22T13:00:00Z",
    "Lunch was lovely. Next time it is my treat, I insist.\n\nSam", 0, "thanks")
add("b291", "Hana Sato", "hana.sato@example.org", "tea", "2026-11-23T10:00:00Z",
    "I left the green tea with your neighbour at number 12, since you were out.\n\nHana", 0, "news")
add("b292", "Priya Shah", "priya.shah@example.com", "Re: visit", "2026-11-24T09:00:00Z",
    "We loved seeing you yesterday. Asha smiled at you, I am sure of it.\n\nPriya", 0, "thanks")
add("b293", "Tomasz Wolak", "t.wolak@example.com", "Re: travel claim", "2026-11-25T11:00:00Z",
    "Hi Maya,\n\nYour travel claim is approved. The money comes with the December pay.\n\nTomasz", 0, "news")
add("b294", "Ben Ortiz", "ben.ortiz@example.net", "Re: workshop", "2026-11-26T15:00:00Z",
    "Hi Maya,\n\nWe cancelled the workshop on Friday. You can have the afternoon back.\n\nBen", 0, "news")
add("b295", "Lena Fischer", "lena.fischer@example.org", "Re: report", "2026-11-27T10:00:00Z",
    "Hi Maya,\n\nThe report is with the client. I sent it this morning, so it is off your list.\n\nLena", 0, "done")
add("b296", "Joe Varga", "joe.varga@example.net", "photos", "2026-11-28T20:00:00Z",
    "Here are the photos from the walk. The one of the bridge is my favourite.\n\nJoe", 0, "news")
add("b297", "Grace Kim", "grace.kim@example.net", "Re: party money", "2026-11-23T09:00:00Z",
    "Hi Maya,\n\nThanks, your share for the dinner came through. We are all square now.\n\nxx G", 0, "thanks")
add("b298", "Ade Okonjo", "ade.okonjo@example.com", "the album", "2026-11-27T18:00:00Z",
    "The album came today and it is beautiful. Rosa cried a little. Thank you for your help with it.\n\nAde", 0, "thanks")
add("b299", "Mum", "anita.rao@example.com", "home safe", "2026-12-26T21:00:00Z",
    "Maya love,\n\nWe got home safe. Thank you for a lovely Christmas. Dad says the turkey was the best yet.\n\nMum", 0, "thanks")
add("b300", "Nina Holt", "nina.holt@example.net", "random", "2026-11-30T23:00:00Z",
    "cannot sleep. watching old cooking shows. why do they always have a perfect one ready in the oven?\n\nn", 0, "chat")
