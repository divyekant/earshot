# Flags v2, build-a, part 4: plain messages with no request (newsletters, receipts, notices, auto replies, own, junk).
# Each message is written by hand, one by one.
from part1 import add, M

L = dict(lst=True, prec="bulk")
# Newsletters and list mail.
add("b131", "Mill Park Friends", "news@millparkfriends.example.org", "November news", "2026-11-02T08:00:00Z",
    "Hello friends,\n\nThe new benches are in and the pond clean-up raised 340 pounds. Our next walk is on 6 December.\n\nMill Park Friends", 0, "newsletter", **L)
add("b132", "Bookfair Online", "news@bookfair.example.com", "New this week: winter reads", "2026-11-02T09:00:00Z",
    "This week: ten books for long evenings, an interview with Ana Ruiz, and our top cookbooks.\n\nBookfair", 0, "newsletter", **L)
add("b133", "Westfield Council", "news@westfield.example.gov", "Westfield this month", "2026-11-03T07:00:00Z",
    "Bin collections move by one day over Christmas. The library opens late on Thursdays from December. Road works on Mill Lane end on the 20th.\n\nWestfield Council", 0, "newsletter", **L)
add("b134", "Fitzone Gym", "news@fitzone.example.com", "Your Fitzone November", "2026-11-03T06:30:00Z",
    "New classes: spin at 7am, yoga on Sundays. Our pool closes for repairs from 10 to 14 November.\n\nFitzone", 0, "newsletter", **L)
add("b135", "Elm Park PTA", "pta@elmpark.example.sch.uk", "[PTA] Christmas fair helpers", "2026-11-04T19:00:00Z",
    "Dear all,\n\nThe Christmas fair is on 5 December. We need helpers for the cake stall and the raffle. Please sign up on the sheet in the office.\n\nElm Park PTA", 0, "list", to=["parents@elmpark.example.sch.uk"], **L)
add("b136", "Casa Verde", "news@casaverde.example.com", "What's cooking in November", "2026-11-04T10:00:00Z",
    "Our chef went to Sicily and brought back three new dishes. Try the lemon pasta from next week.\n\nCasa Verde", 0, "newsletter", **L)
add("b137", "Riverside Water", "news@riversidewater.example.com", "Winter tips", "2026-11-05T07:00:00Z",
    "Cold nights are coming. Keep your pipes warm, and know where your stop tap is.\n\nRiverside Water", 0, "newsletter", **L)
add("b138", "Fenwick News", "news@fenwick.example.com", "Fenwick weekly", "2026-11-05T08:00:00Z",
    "This week: a new client in Leeds, the winter party date, and our charity bake sale raised 600 pounds.\n\nInternal Comms", 0, "newsletter", to=["all-staff@fenwick.example.com"], **L)
add("b139", "Hill Runners", "list@hillrunners.example.org", "[Hill Runners] Sunday route", "2026-11-06T20:00:00Z",
    "Sunday we run the canal route, 12 km, meet at the lock at 9. Bring a light, it is dark at the end.\n\nCoach Mike", 0, "list", to=["members@hillrunners.example.org"], **L)
add("b140", "Travelnest", "news@travelnest.example.com", "Ideas for winter sun", "2026-11-06T06:00:00Z",
    "Five islands with sun in January, and how to pack light for a weekend.\n\nTravelnest", 0, "newsletter", **L)
add("b141", "Northside Library", "news@northsidelibrary.example.org", "Library news", "2026-11-07T09:00:00Z",
    "Author talk with Sam Bright on the 12th. Story time moves to Saturday mornings.\n\nNorthside Library", 0, "newsletter", **L)
add("b142", "Halden Bank", "news@haldenbank.example.com", "Your money this winter", "2026-11-08T08:00:00Z",
    "Tips to plan your holiday spending, and how our new app helps you save.\n\nHalden Bank", 0, "newsletter", **L)
add("b143", "Pet Corner", "news@petcorner.example.com", "Pet care in the cold", "2026-11-09T09:00:00Z",
    "Dogs feel the cold too. Read our guide to winter walks and paw care.\n\nPet Corner", 0, "newsletter", **L)
add("b144", "Book Club", "list@bookclub-north.example.org", "[Book club] December meeting", "2026-11-10T18:00:00Z",
    "Hi all,\n\nThe December meeting is at Hana's on the 3rd at 7pm. We read 'The Salt Path'. Bring a snack if you like.\n\nHana", 0, "list", to=["members@bookclub-north.example.org"], **L)
add("b145", "Lumen Home", "news@lumenhome.example.com", "Ideas for a cosy home", "2026-11-10T12:00:00Z",
    "Warm light, soft throws and the colours of the season. See our winter guide.\n\nLumen Home", 0, "newsletter", **L)
add("b146", "Green Street Residents", "list@greenstreet.example.org", "[Residents] parking meeting notes", "2026-11-11T21:00:00Z",
    "Notes from Tuesday: the council will paint new lines in January. The next meeting is in February.\n\nAli", 0, "list", to=["residents@greenstreet.example.org"], **L)
add("b147", "Swift Cars", "news@swiftcars.example.com", "Drive safe this winter", "2026-11-12T07:00:00Z",
    "Check your tyres, your lights and your wipers. Our winter guide has all you need.\n\nSwift Cars", 0, "newsletter", **L)
add("b148", "Fenwick IT", "it-news@fenwick.example.com", "IT update", "2026-11-13T08:00:00Z",
    "The email system has maintenance on Saturday night from 22:00 to 02:00. You do not need to do anything.\n\nFenwick IT", 0, "notice", to=["all-staff@fenwick.example.com"], **L)
add("b149", "Hill Runners", "list@hillrunners.example.org", "[Hill Runners] Re: Sunday route", "2026-11-07T08:00:00Z",
    "Mike, can we start at 9:30 instead? The car park opens late on Sundays.\n\nSteve", 0, "list", to=["members@hillrunners.example.org"], **L)
add("b150", "Elm Park PTA", "pta@elmpark.example.sch.uk", "[PTA] thank you!", "2026-11-14T19:00:00Z",
    "Dear all,\n\nThe cake sale raised 412 pounds. Thank you to everyone who baked.\n\nElm Park PTA", 0, "list", to=["parents@elmpark.example.sch.uk"], **L)
add("b151", "Bookfair Online", "news@bookfair.example.com", "Gift guide", "2026-11-15T09:00:00Z",
    "Books for everyone on your list, from 5 pounds. Free wrap on all orders this month.\n\nBookfair", 0, "newsletter", **L)
add("b152", "Westfield Council", "news@westfield.example.gov", "Christmas lights switch-on", "2026-11-16T07:00:00Z",
    "The lights go on in the market square on 28 November at 5pm. There will be music and food stalls.\n\nWestfield Council", 0, "newsletter", **L)
add("b153", "Mill Park Friends", "news@millparkfriends.example.org", "Tree planting day", "2026-11-17T08:00:00Z",
    "We plant 40 trees on Saturday 5 December. Volunteers are welcome from 10am, bring gloves.\n\nMill Park Friends", 0, "newsletter", **L)
add("b154", "Fenwick News", "news@fenwick.example.com", "Fenwick weekly", "2026-11-19T08:00:00Z",
    "This week: Leeds office opens, new coffee machine on floor 4, and the winter party is on 17 December.\n\nInternal Comms", 0, "newsletter", to=["all-staff@fenwick.example.com"], **L)
add("b155", "Travelnest", "news@travelnest.example.com", "Your weekend in Porto", "2026-11-20T06:00:00Z",
    "Porto in winter: rain, port wine and quiet streets. Our guide to 48 hours.\n\nTravelnest", 0, "newsletter", **L)

# Receipts and confirmations.
add("b156", "Lumen Home", "orders@lumenhome.example.com", "Order 41794 confirmed", "2026-11-02T14:00:00Z",
    "Hello Maya,\n\nThank you for your order of the Calm sofa. We received your payment of 649.00 pounds.\n\nLumen Home", 0, "receipt")
add("b157", "Bookfair Online", "orders@bookfair.example.com", "Your order has shipped", "2026-11-03T16:00:00Z",
    "Hi Maya,\n\nOrder BF-22018 is on its way. It should arrive on Thursday.\n\nBookfair", 0, "receipt")
add("b158", "Halden Bank", "alerts@haldenbank.example.com", "Payment sent", "2026-11-04T12:00:00Z",
    "You sent 85.00 pounds to R Patel. Reference: van.\n\nHalden Bank", 0, "receipt")
add("b159", "Casa Verde", "bookings@casaverde.example.com", "Booking confirmed", "2026-11-05T11:00:00Z",
    "Hi Maya,\n\nYour table for 8 on 21 November at 19:30 is booked. See you then!\n\nCasa Verde", 0, "receipt")
add("b160", "Travelnest", "bookings@travelnest.example.com", "Your trip to Lisbon", "2026-11-11T23:00:00Z",
    "Booking TN-55120 is confirmed: 3 nights at Hotel Rio, 12 to 15 March, for 2 guests. Total paid: 312 pounds.\n\nTravelnest", 0, "receipt")
add("b161", "Riverside Water", "billing@riversidewater.example.com", "Payment received", "2026-11-12T06:00:00Z",
    "Dear customer,\n\nThank you. We received 61.40 pounds for account 55031-7.\n\nRiverside Water", 0, "receipt")
add("b162", "Orbit Parcel", "notify@orbitparcel.example.com", "Delivered", "2026-11-13T15:00:00Z",
    "Your parcel OP-80233 was delivered to your door at 14:52.\n\nOrbit Parcel", 0, "receipt")
add("b163", "Swift Cars", "service@swiftcars.example.com", "Your invoice", "2026-11-14T17:00:00Z",
    "Dear Maya,\n\nInvoice SC-1192 for the MOT and the new wiper blades: 78.50 pounds, paid by card.\n\nSwift Cars", 0, "receipt")
add("b164", "Fitzone Gym", "billing@fitzone.example.com", "Membership cancelled", "2026-11-02T10:00:00Z",
    "Hi Maya,\n\nYour membership ends on 30 November as asked. You will not be charged again.\n\nFitzone", 0, "receipt")
add("b165", "Pet Corner", "orders@petcorner.example.com", "Thanks for your order", "2026-11-15T09:30:00Z",
    "Order PC-4471: 2 bags of cat food. It ships tomorrow.\n\nPet Corner", 0, "receipt")
add("b166", "Westfield Recycling", "waste@westfield.example.gov", "Permit renewed", "2026-11-19T08:00:00Z",
    "Dear Maya Rao,\n\nYour garden waste permit GW-6620 is renewed until 31 December next year.\n\nWestfield Council", 0, "receipt")
add("b167", "Brightwave Broadband", "billing@brightwave.example.com", "Your bill is ready", "2026-11-16T07:00:00Z",
    "Hello Maya,\n\nYour November bill is 32.00 pounds. It will be taken by direct debit on 1 December. You do not need to do anything.\n\nBrightwave", 0, "receipt")
add("b168", "Greenline Energy", "billing@greenline.example.com", "Your statement", "2026-11-17T07:00:00Z",
    "Dear Maya Rao,\n\nYour statement for October is ready in your account. Your balance is 12.40 pounds in credit.\n\nGreenline Energy", 0, "receipt")
add("b169", "Northside Library", "loans@northsidelibrary.example.org", "Items renewed", "2026-11-12T10:00:00Z",
    "Dear Maya Rao,\n\nYour 2 items are renewed until 4 December.\n\nNorthside Library", 0, "receipt")
add("b170", "Clarke Insurance", "policies@clarkeinsurance.example.com", "Your renewal documents", "2026-11-25T07:00:00Z",
    "Dear Ms Rao,\n\nPolicy HM-30219 is renewed. Your documents are attached. The price is 214 pounds a year, paid monthly.\n\nClarke Insurance", 0, "receipt")
add("b171", "Halden Bank", "alerts@haldenbank.example.com", "Card payment", "2026-11-18T19:00:00Z",
    "A payment of 23.80 pounds to Casa Verde was made with your card ending 4410.\n\nHalden Bank", 0, "receipt")
add("b172", "PrintHouse", "orders@printhouse.example.com", "Order dispatched", "2026-11-21T12:00:00Z",
    "Hi Maya,\n\n500 leaflets are on the way to Fenwick, reception. Tracking: PH-3301.\n\nPrintHouse", 0, "receipt")
add("b173", "Harbour Dental", "reception@harbourdental.example.com", "Receipt for your visit", "2026-11-18T11:00:00Z",
    "Dear Ms Rao,\n\nThank you for your visit today. Paid: 25.00 pounds.\n\nHarbour Dental", 0, "receipt")
add("b174", "Bookfair Online", "orders@bookfair.example.com", "Refund issued", "2026-11-19T10:00:00Z",
    "Hi Maya,\n\nWe refunded 12.99 pounds for the damaged book. It shows on your card in 3 to 5 days.\n\nBookfair", 0, "receipt")
add("b175", "Fenwick Payroll", "payroll@fenwick.example.com", "Your payslip", "2026-11-27T08:00:00Z",
    "Hello Maya,\n\nYour November payslip is now on the staff page.\n\nPayroll", 0, "receipt")

# Notices with a date and nothing to do.
add("b176", "Riverside Water", "service@riversidewater.example.com", "Work on your street", "2026-11-06T07:00:00Z",
    "Dear customer,\n\nWe will replace a pipe on Elm Road on 19 November. Your water may be off from 9am to 1pm.\n\nRiverside Water", 0, "notice")
add("b177", "Fenwick Facilities", "facilities@fenwick.example.com", "Fire drill", "2026-11-09T08:00:00Z",
    "There is a fire drill on Wednesday at 11am. It takes about 15 minutes.\n\nFacilities", 0, "notice", to=["all-staff@fenwick.example.com"])
add("b178", "Northside Library", "notices@northsidelibrary.example.org", "Closed on Monday", "2026-11-12T09:00:00Z",
    "The library is closed on Monday 16 November for staff training. Online loans still work.\n\nNorthside Library", 0, "notice")
add("b179", "Elm Park Primary", "office@elmpark.example.sch.uk", "Inset day", "2026-11-13T08:00:00Z",
    "Dear Parent,\n\nA reminder that school is closed on Friday 27 November for staff training.\n\nElm Park Primary School", 0, "notice", to=["parents@elmpark.example.sch.uk"])
add("b180", "Halden Bank", "service@haldenbank.example.com", "App update on Sunday", "2026-11-14T08:00:00Z",
    "Our app will be off on Sunday from 1am to 4am for an update. Your card still works.\n\nHalden Bank", 0, "notice")
add("b181", "Westfield Recycling", "waste@westfield.example.gov", "Christmas collections", "2026-11-23T07:00:00Z",
    "Your bin day moves from Thursday to Saturday in the week of 25 December.\n\nWestfield Council", 0, "notice")
add("b182", "Orbit Parcel", "notify@orbitparcel.example.com", "Your parcel is on its way", "2026-11-24T09:00:00Z",
    "Parcel OP-81920 from Bookfair arrives tomorrow between 10:00 and 12:00.\n\nOrbit Parcel", 0, "notice")
add("b183", "Brightwave Broadband", "service@brightwave.example.com", "Planned work", "2026-11-25T08:00:00Z",
    "Your internet may be slow on 2 December between midnight and 6am while we upgrade the area.\n\nBrightwave", 0, "notice")
add("b184", "Mehta Surgery", "appointments@mehtasurgery.example.nhs.uk", "Reminder: your review", "2026-12-02T08:00:00Z",
    "Dear Maya Rao,\n\nThis is a reminder of your review with Dr Mehta on 4 December at 10:40.\n\nMehta Surgery", 0, "notice")
add("b185", "Lumen Home", "orders@lumenhome.example.com", "Your delivery is tomorrow", "2026-12-01T16:00:00Z",
    "Hello Maya,\n\nYour sofa arrives tomorrow between 8 and 12. The driver will call 30 minutes before.\n\nLumen Home", 0, "notice")
add("b186", "Greenline Energy", "accounts@greenline.example.com", "Your price from January", "2026-11-20T07:00:00Z",
    "Dear Maya Rao,\n\nYour fixed deal ends on 31 March. From January the unit price stays the same. We will write again before the end.\n\nGreenline Energy", 0, "notice")
add("b187", "Fenwick IT", "it@fenwick.example.com", "Password expires in 10 days", "2026-11-20T08:00:00Z",
    "Your password will be changed for you on the next login. No action is needed now.\n\nFenwick IT", 0, "notice", auto=True)
add("b188", "Swift Cars", "service@swiftcars.example.com", "MOT booked", "2026-11-21T09:00:00Z",
    "Dear Maya,\n\nYour MOT is booked for 1 December at 9:00. Please leave the car with us by 8:45.\n\nSwift Cars", 0, "notice")
add("b189", "Elm Park Primary", "office@elmpark.example.sch.uk", "Year 3 trip times", "2026-11-26T08:00:00Z",
    "Dear Parent,\n\nThe coach leaves at 9:00 on 2 December and comes back at 15:30. Children need a packed lunch.\n\nElm Park Primary School", 0, "notice", to=["year3@elmpark.example.sch.uk"])
add("b190", "Travelnest", "bookings@travelnest.example.com", "Check-in opens soon", "2026-11-27T06:00:00Z",
    "Your hotel in Lisbon opens online check-in 48 hours before your stay. We will send you a link.\n\nTravelnest", 0, "notice")

# Automatic answers.
A = dict(auto=True, prec="auto_reply")
add("b191", "Lena Fischer", "lena.fischer@example.org", "Out of office: Monday call", "2026-11-03T09:11:00Z",
    "I am out of the office until 9 November with no access to mail. For urgent matters, please call Paul Evans.", 0, "auto_reply", **A)
add("b192", "Sofia Marin", "sofia.marin@example.org", "Automatic reply", "2026-11-08T11:16:00Z",
    "Thank you for your mail. I am on leave until Monday. I will reply when I am back.", 0, "auto_reply", **A)
add("b193", "Fenwick HR", "hr@fenwick.example.com", "We received your message", "2026-11-11T12:01:00Z",
    "Thank you for contacting HR. We answer within two working days. Ticket number: HR-55021.", 0, "auto_reply", **A)
add("b194", "Clarke Insurance", "policies@clarkeinsurance.example.com", "Re: policy question", "2026-11-09T10:02:00Z",
    "We have your message and will reply within 3 working days. Please do not reply to this mail.", 0, "auto_reply", **A)
add("b195", "Martin Leclerc", "martin.leclerc@example.com", "Out of office", "2026-11-20T09:00:00Z",
    "I am travelling until 24 November. Please send contract questions to Sofia Marin.", 0, "auto_reply", **A)

# From the owner (own address), and junk.
add("b196", "Maya Rao", M, "note to self", "2026-11-04T22:00:00Z",
    "Call the bank tomorrow about the card limit. Book the MOT.", 0, "own", to=[M])
add("b197", "Maya Rao", M, "Fwd: Lisbon hotel", "2026-11-12T08:00:00Z",
    "For the trip folder.\n\n---------- Forwarded message ---------\nBooking TN-55120 is confirmed.", 0, "own", to=[M])
add("b198", "Prize Centre", "winner@prize-centre.example.biz", "You have won!", "2026-11-05T03:00:00Z",
    "Dear winner, claim your prize of 5000 pounds now. Send your bank details today.", 0, "junk", junk=True)
add("b199", "Account Team", "security@halden-bank-secure.example.biz", "Urgent: account locked", "2026-11-09T04:00:00Z",
    "Your account is locked. Click the link and enter your password within 24 hours.", 0, "junk", junk=True)
add("b200", "Pharma Deals", "deals@pharma-deals.example.biz", "Cheap meds", "2026-11-14T02:00:00Z",
    "Best prices online. Order now and pay later.", 0, "junk", junk=True)
