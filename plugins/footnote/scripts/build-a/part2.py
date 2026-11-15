# Flags v2, build-a, part 2: hard messages with no request (to another person; sales and surveys with no list header).
# Each message is written by hand, one by one.
from part1 import add, R, M

# A request to another person, with the owner in To or Cc.
add("b046", "Lena Fischer", "lena.fischer@example.org", "Monday call", "2026-11-03T09:10:00Z",
    "Hi Paul,\n\nCould you send the agenda to the client by Friday? Maya is in copy so she knows the time.\n\nLena",
    0, "other-person", to=["paul.evans@example.com"], cc=[M])
add("b047", "Grace Kim", "grace.kim@example.net", "Ben's party", "2026-11-03T18:30:00Z",
    "Tom, can you get the cake from the bakery on Saturday morning? Maya and I will do the drinks.\n\nGrace",
    0, "other-person", to=["tom.hale@example.com", M])
add("b048", "Paul Evans", "paul.evans@example.com", "Re: slides", "2026-11-04T10:00:00Z",
    "Ana,\n\nPlease add the cost table to slide 6 before lunch. Maya already checked the text.\n\nPaul",
    0, "other-person", to=["ana.silva@example.com"], cc=[M])
add("b049", "Mum", "anita.rao@example.com", "Sunday lunch", "2026-11-04T20:20:00Z",
    "Dear Vik, dear Maya,\n\nVik, please pick up Granny at 12 on Sunday. She does not want to take the bus.\n\nMum",
    0, "other-person", to=["vik.rao@example.com", M])
add("b050", "Kofi Mensah", "kofi.mensah@example.net", "club accounts", "2026-11-05T08:50:00Z",
    "Hello Daniel,\n\nThe bank wants the signed accounts by the 30th. Can you sign them when you are in on Tuesday?\n\nKofi\n(cc Maya for the records)",
    0, "other-person", to=["d.brandt@example.com"], cc=[M])
add("b051", "Julia Costa", "julia.costa@example.org", "Q4 pack", "2026-11-05T14:00:00Z",
    "Team,\n\nOmar, I need the sales numbers from you by Wednesday. Lena, please check the travel line. Thanks all.\n\nJulia",
    0, "other-person", to=["omar.haddad@example.org", "lena.fischer@example.org", M, "will.grant@example.com"])
add("b052", "Hana Sato", "hana.sato@example.org", "book club host", "2026-11-06T12:00:00Z",
    "Hi Rosa,\n\nWould you host in February? Maya hosted last time and the group says it is your turn.\n\nHana",
    0, "other-person", to=["rosa.diaz@example.net"], cc=[M])
add("b053", "Ravi Patel", "ravi.patel@example.com", "van on the 14th", "2026-11-06T19:00:00Z",
    "Noah - the van is booked. You need to be at the depot by 8 to sign for it. Maya, nothing for you, just so you know.\n\nRavi",
    0, "other-person", to=["noah.brooks@example.com", M])
add("b054", "Fenwick Facilities", "facilities@fenwick.example.com", "Desk move", "2026-11-07T09:00:00Z",
    "Dear Will,\n\nPlease clear your desk on the 3rd floor by Thursday 5pm. Your new desk is next to Maya Rao on the 4th floor.\n\nFacilities",
    0, "other-person", to=["will.grant@example.com"], cc=[M])
add("b055", "Irene Castell", "irene.castell@example.org", "Re: keys", "2026-11-07T21:10:00Z",
    "Joe, could you give Maya the spare key when you see her? I am away until Monday.\n\nIrene",
    0, "other-person", to=["joe.varga@example.net"], cc=[M])
add("b056", "Elm Park Primary", "office@elmpark.example.sch.uk", "Message for Mr Rao", "2026-11-08T08:30:00Z",
    "Dear Mr Rao,\n\nLeo's swimming kit was left at school. Please collect it from the office on Friday.\n\nElm Park Primary School",
    0, "other-person", to=["vik.rao@example.com"], cc=[M])
add("b057", "Martin Leclerc", "martin.leclerc@example.com", "clause 7", "2026-11-08T11:15:00Z",
    "Sofia,\n\nCould you ask legal for their view on clause 7 by Tuesday? I copied Maya so she sees the thread.\n\nMartin",
    0, "other-person", to=["sofia.marin@example.org"], cc=[M])
add("b058", "Rosa Diaz", "rosa.diaz@example.net", "Christmas plan", "2026-11-09T19:40:00Z",
    "Tom,\n\nCan you order the turkey this week? The butcher closes the list on Friday.\n\nRosa\n\n(Maya, I will write to you about the desserts later.)",
    0, "other-person", to=["tom.hale@example.com", M])
add("b059", "Omar Haddad", "omar.haddad@example.org", "landlord", "2026-11-09T16:00:00Z",
    "Hi Ali,\n\nThe landlord wants the hedge cut before the inspection on the 25th. Can you call the gardener? I have put Maya on this so she knows.\n\nOmar",
    0, "other-person", to=["ali.reed@example.net"], cc=[M])
add("b060", "Ben Ortiz", "ben.ortiz@example.net", "final version", "2026-11-10T09:00:00Z",
    "Ana, please send the final version to the printer today. Maya signed it off yesterday.\n\nBen",
    0, "other-person", to=["ana.silva@example.com", M])
add("b061", "Jo Turner", "jo.turner@example.net", "cat sitting", "2026-11-10T20:00:00Z",
    "Hi Nina,\n\nCould you do Friday evening for Pepper? Maya can do the weekend.\n\nThanks so much,\nJo",
    0, "other-person", to=["nina.holt@example.net"], cc=[M])
add("b062", "Priya Shah", "priya.shah@example.com", "Lisbon flights", "2026-11-11T22:00:00Z",
    "Joe, can you book the flights for the three of us tonight? Maya said yes, I said yes, so it's just you now.\n\nP",
    0, "other-person", to=["joe.varga@example.net", M])
add("b063", "Anna Novak", "anna.novak@example.org", "invoice 2207", "2026-11-12T08:10:00Z",
    "Dear Martin,\n\nPlease approve invoice 2207 in the system before Friday. Maya already signed the form.\n\nRegards,\nAnna",
    0, "other-person", to=["martin.leclerc@example.com"], cc=[M])
add("b064", "Sam Lee", "sam.lee@example.net", "team list", "2026-11-13T17:30:00Z",
    "Hi all,\n\nDan, I still need your form before the 20th. Everyone else is done, thanks!\n\nSam",
    0, "other-person", to=["dan.ross@example.com", M, "lena.fischer@example.org"])
add("b065", "Chiara Russo", "chiara.russo@example.org", "room for Thursday", "2026-11-14T09:00:00Z",
    "Will - can you set up the screen in the small room before 10 on Thursday? Maya booked the room.\n\nChiara",
    0, "other-person", to=["will.grant@example.com", M])

# Sales and surveys with no list header. Some use request words and a time limit.
add("b066", "Lumen Home", "offers@lumenhome.example.com", "Your sofa deserves a friend", "2026-11-03T10:00:00Z",
    "Hi Maya,\n\nOrder the matching armchair by Sunday and save 20%. Use code CALM20 at the checkout.\n\nLumen Home",
    0, "sales")
add("b067", "Clarke Insurance", "hello@clarkeinsurance.example.com", "How did we do?", "2026-11-03T12:00:00Z",
    "Dear Maya,\n\nYou spoke to our team last week. Could you rate the call from 1 to 5? It takes one minute.\n\nClarke Insurance",
    0, "survey")
add("b068", "Fitzone Gym", "team@fitzone.example.com", "Come back to Fitzone", "2026-11-04T07:00:00Z",
    "Maya, we miss you! Sign up again before 30 November and your first month is free.\n\nFitzone",
    0, "sales")
add("b069", "Halden Bank", "offers@haldenbank.example.com", "A better rate for you", "2026-11-04T09:30:00Z",
    "Dear Ms Rao,\n\nDo you know what your savings earn? Move them to our Plus account by Friday and get 4.1%.\n\nHalden Bank",
    0, "sales")
add("b070", "Orbit Parcel", "feedback@orbitparcel.example.com", "Tell us about your delivery", "2026-11-05T13:00:00Z",
    "Hello Maya,\n\nWould you recommend Orbit Parcel to a friend? Answer one question and win a 50 pound voucher.\n\nOrbit Parcel",
    0, "survey")
add("b071", "Brightwave Broadband", "sales@brightwave.example.com", "Faster internet on Elm Road", "2026-11-05T15:00:00Z",
    "Hello Maya,\n\nFull fibre is now on your street. Call us this week to book your free upgrade, from 25 pounds a month.\n\nBrightwave",
    0, "sales")
add("b072", "Harbour Dental", "hello@harbourdental.example.com", "Whiter teeth for the holidays", "2026-11-06T10:00:00Z",
    "Dear Maya,\n\nBook a whitening session before 15 December and get 30% off. Reply to this mail or call the front desk.\n\nHarbour Dental",
    0, "sales")
add("b073", "Westfield Council", "consult@westfield.example.gov", "Have your say on the new park", "2026-11-06T11:00:00Z",
    "Dear resident,\n\nWe want your opinion on the plans for Mill Park. Please fill in our short survey by 30 November.\n\nWestfield Council",
    0, "survey")
add("b074", "Casa Verde", "bookings@casaverde.example.com", "Your table for the festive season", "2026-11-07T16:00:00Z",
    "Hi Maya,\n\nOur Christmas menu is out. Book your table before the 1st and get a free glass of prosecco. Limited places!\n\nCasa Verde",
    0, "sales")
add("b075", "Greenline Energy", "deals@greenline.example.com", "Fix your price now", "2026-11-07T08:00:00Z",
    "Dear Maya Rao,\n\nPrices may go up in January. Confirm your new fixed deal by 20 November to lock in today's rate.\n\nGreenline Energy",
    0, "sales")
add("b076", "Bookfair Online", "reviews@bookfair.example.com", "How was 'Bread at Home'?", "2026-11-08T09:00:00Z",
    "Hi Maya,\n\nYou bought 'Bread at Home' last month. Would you write a short review for other readers?\n\nBookfair",
    0, "survey")
add("b077", "Swift Cars", "info@swiftcars.example.com", "Your car is due a service", "2026-11-08T10:30:00Z",
    "Dear Maya,\n\nWinter is coming. Book your winter check with us this month and the battery test is free. Call 0161 496 0777.\n\nSwift Cars",
    0, "sales")
add("b078", "Fenwick People Team", "survey@fenwick.example.com", "Your first weeks: a short survey", "2026-11-09T08:00:00Z",
    "Hello,\n\nWe want to know how your start went. Please give us your feedback by Friday. It takes five minutes.\n\nFenwick People Team",
    0, "survey", to=["staff-new@fenwick.example.com"])
add("b079", "Lumen Home", "offers@lumenhome.example.com", "Last chance: 40% off lamps", "2026-11-09T18:00:00Z",
    "Maya, the sale ends tonight at midnight. Don't miss it - shop now.\n\nLumen Home",
    0, "sales")
add("b080", "PrintHouse", "sales@printhouse.example.com", "Re: your quote", "2026-11-10T11:00:00Z",
    "Hi Maya,\n\nWe can print your leaflets from 9 pounds per 100. Send us your design by Thursday and get your quote in 24 hours.\n\nPrintHouse",
    0, "sales")
add("b081", "Riverside Water", "news@riversidewater.example.com", "Save water, save money", "2026-11-10T07:00:00Z",
    "Dear customer,\n\nOrder your free water-saving kit today. Fill in the form on our site before the end of the month.\n\nRiverside Water",
    0, "sales")
add("b082", "Travelnest", "deals@travelnest.example.com", "Lisbon from 89 pounds", "2026-11-11T06:00:00Z",
    "Maya, you looked at Lisbon. Book by Sunday and save up to 25% on hotels. Prices change fast!\n\nTravelnest",
    0, "sales")
add("b083", "Halden Bank", "survey@haldenbank.example.com", "One question about the app", "2026-11-11T12:00:00Z",
    "Dear Ms Rao,\n\nHow easy was it to confirm your address in the app? Click a number from 1 to 10.\n\nHalden Bank",
    0, "survey")
add("b084", "Pet Corner", "hello@petcorner.example.com", "Pepper's food", "2026-11-12T09:00:00Z",
    "Hi Maya,\n\nWe think Pepper will love our new winter food. Try a bag at half price - offer valid until Sunday.\n\nPet Corner",
    0, "sales")
add("b085", "Northside Library", "events@northsidelibrary.example.org", "Join our reading challenge", "2026-11-12T10:00:00Z",
    "Dear Maya,\n\nSign up for the winter reading challenge by 30 November and win a book token. Ask at the desk.\n\nNorthside Library",
    0, "sales")
add("b086", "Swift Cars", "feedback@swiftcars.example.com", "Your MOT visit", "2026-11-13T15:00:00Z",
    "Dear Maya,\n\nThank you for your visit. Could you spare two minutes to tell us what you think? Your opinion helps us improve.\n\nSwift Cars",
    0, "survey")
add("b087", "Brightwave Broadband", "offers@brightwave.example.com", "Re: Faster internet on Elm Road", "2026-11-14T10:00:00Z",
    "Hello Maya,\n\nOnly 5 free install slots left this month. Reply YES by Friday and we will call you.\n\nBrightwave",
    0, "sales")
add("b088", "Casa Verde", "feedback@casaverde.example.com", "How was your evening?", "2026-11-15T11:00:00Z",
    "Hi Maya,\n\nYou dined with us on Saturday. Would you tell other guests what you think? Leave a review and get a free dessert next time.\n\nCasa Verde",
    0, "survey")
add("b089", "Fitzone Gym", "team@fitzone.example.com", "Your free trial pass", "2026-11-16T07:30:00Z",
    "Maya, bring a friend this week! Show this mail at the desk before Sunday to get two free passes.\n\nFitzone",
    0, "sales")
add("b090", "Clarke Insurance", "sales@clarkeinsurance.example.com", "Car insurance quote", "2026-11-17T09:00:00Z",
    "Dear Maya,\n\nYour home policy renews soon. Add car cover before 1 December and save 15% on both. Call us for a quote.\n\nClarke Insurance",
    0, "sales")
