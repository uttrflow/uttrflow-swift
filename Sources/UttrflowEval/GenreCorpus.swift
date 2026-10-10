// Invented whole dictations, three in each writing genre, each scored as one text. See Docs/genre-matrix.md.
import UttrflowCore

extension EvaluationCorpus {
    /// Kept out of `all`, and so out of the meaning-guard refusal gate, while that guard refuses 34 of their references.
    public static let genres: [EvaluationCase] =
        correspondence + workWriting + everydayWriting + formalWriting + creativeWriting + mixedSpeech

    /// A genre case: the whole text a person writes, with everything they said kept and nothing they did not.
    private static func piece(
        _ genre: Genre, _ id: String, _ spoken: String, _ expected: String,
        keep: [String], notAdd: [String], classes: [FormattingClass],
        category: EvaluationCase.Category = .everyday, context: AppContext = .unknown
    ) -> EvaluationCase {
        .init(
            id: "genre-\(genre.rawValue)-\(id)", category: category, spoken: spoken, expected: expected,
            mustKeep: keep, context: context, mustNotAdd: notAdd, classes: classes, genre: genre,
            addedFor: 3840)
    }

    /// A whole text that opens with a break starts an empty field, so the break has nothing to break from.
    static let emptyField = AppContext(precedingText: "")

    static let correspondence: [EvaluationCase] = [
        piece(
            .customerEmail, "late-parcel",
            "hi jonah thanks for getting in touch about order four eight one seven two. the parcel left our warehouse on the third of june and the courier now expects it by friday. i have refunded the twelve dollars shipping fee to your card. new paragraph if it has not arrived by monday just reply to this email and we will send a replacement. best wishes mira",
            "Hi Jonah, thanks for getting in touch about order 48172. The parcel left our warehouse on the 3rd of June and the courier now expects it by Friday. I have refunded the 12 dollars shipping fee to your card.\n\nIf it has not arrived by Monday, just reply to this email and we will send a replacement. Best wishes, Mira",
            keep: ["48172", "Friday", "replacement"], notAdd: ["apologise", "sorry"],
            classes: [.numbers, .paragraphs, .capitalisationAndTokens, .commas]),
        piece(
            .customerEmail, "account-question",
            "hello and thank you for your question. your plan renews on the fourteenth of august at nine dollars ninety nine a month. you can switch to the yearly plan from the billing page which works out at about eighty dollars a year. if anything is unclear write to help at example dot com and quote ticket q r seven seven one. kind regards tobin",
            "Hello and thank you for your question. Your plan renews on the 14th of August at $9.99 a month. You can switch to the yearly plan from the billing page, which works out at about 80 dollars a year. If anything is unclear, write to help@example.com and quote ticket QR771. Kind regards, Tobin",
            keep: ["help@example.com", "billing", "yearly"], notAdd: ["discount", "free"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .customerEmail, "booking-change",
            "dear guest your booking for two adults has moved from room two one four to room three zero two because of a leak. the new room has the same view and a larger balcony. breakfast is served from seven until ten thirty in the garden cafe. please let us know at the front desk if you need a late checkout. warm regards the reception team",
            "Dear guest, your booking for two adults has moved from room 214 to room 302 because of a leak. The new room has the same view and a larger balcony. Breakfast is served from 7 until 10:30 in the garden cafe. Please let us know at the front desk if you need a late checkout. Warm regards, the reception team",
            keep: ["214", "302", "balcony"], notAdd: ["upgrade", "complimentary"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .chatReply, "running-late",
            "hey sorry running about fifteen minutes late the train stopped outside the station. can you grab us a table near the window. i will have the usual if they ask. also did you bring the charger i left at yours last week",
            "Hey, sorry, running about 15 minutes late, the train stopped outside the station. Can you grab us a table near the window? I will have the usual if they ask. Also, did you bring the charger I left at yours last week?",
            keep: ["train", "charger", "window"], notAdd: ["please", "thanks"],
            classes: [.questions, .commas, .numbers]),
        piece(
            .chatReply, "weekend-plan",
            "yes saturday works for me. we could do the lake walk in the morning and then lunch at that place on mill road. it is about six k so bring proper shoes. i can drive if you get the snacks. let me know by thursday so i can book the parking",
            "Yes, Saturday works for me. We could do the lake walk in the morning and then lunch at that place on Mill Road. It is about 6k, so bring proper shoes. I can drive if you get the snacks. Let me know by Thursday so I can book the parking.",
            keep: ["Saturday", "Mill Road", "parking"], notAdd: ["kilometres", "please"],
            classes: [.capitalisationAndTokens, .numbers, .commas]),
        piece(
            .chatReply, "quick-answer",
            "no worries i already sent it. check your spam folder the subject line is invoice for may. if it is not there i can share the link instead. the total is three hundred and forty pounds and the due date is the end of the month",
            "No worries, I already sent it. Check your spam folder, the subject line is invoice for May. If it is not there, I can share the link instead. The total is 340 pounds and the due date is the end of the month.",
            keep: ["spam", "340", "May"], notAdd: ["£", "attached"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .apology, "missed-call",
            "i am really sorry i missed our call this morning. my phone was on silent and i did not see the reminder until ten past eleven. that is on me and not on you. could we try again tomorrow at two or any time on wednesday afternoon. i will keep the whole hour free",
            "I am really sorry I missed our call this morning. My phone was on silent and I did not see the reminder until ten past eleven. That is on me and not on you. Could we try again tomorrow at two or any time on Wednesday afternoon? I will keep the whole hour free.",
            keep: ["silent", "Wednesday", "hour"], notAdd: ["apologies", "unfortunately"],
            classes: [.questions, .sentenceBoundaries, .capitalisationAndTokens]),
        piece(
            .apology, "wrong-figures",
            "team i owe you an apology. the report i sent on monday had the wrong figures for the north region. revenue was one point two million not two point one million. i swapped two digits when copying from the sheet. the corrected file is in the shared folder and i have added a check so this cannot happen again",
            "Team, I owe you an apology. The report I sent on Monday had the wrong figures for the north region. Revenue was 1.2 million, not 2.1 million. I swapped two digits when copying from the sheet. The corrected file is in the shared folder and I have added a check so this cannot happen again.",
            keep: ["1.2 million", "2.1 million", "corrected"], notAdd: ["sorry", "mistake"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .apology, "neighbour-note",
            "hi there i am the neighbour from flat six. i am sorry about the noise on saturday night we had friends over for a birthday and it went on far longer than planned. it will not happen again. if you are around this week i would like to drop off some cake to say sorry properly",
            "Hi there, I am the neighbour from flat 6. I am sorry about the noise on Saturday night, we had friends over for a birthday and it went on far longer than planned. It will not happen again. If you are around this week, I would like to drop off some cake to say sorry properly.",
            keep: ["neighbour", "Saturday", "cake"], notAdd: ["apologise", "party"],
            classes: [.commas, .numbers, .sentenceBoundaries]),
    ]

    static let workWriting: [EvaluationCase] = [
        piece(
            .meetingMinutes, "planning-sync",
            "minutes from the planning sync on the second of october. present were dana leo and priti. first item the launch moves to the twentieth because the payment provider needs another week. second item leo will draft the help pages by friday. third item we agreed to drop the dark mode toggle from this release. next meeting is tuesday at ten",
            "Minutes from the planning sync on the 2nd of October. Present were Dana, Leo and Priti. First item, the launch moves to the 20th because the payment provider needs another week. Second item, Leo will draft the help pages by Friday. Third item, we agreed to drop the dark mode toggle from this release. Next meeting is Tuesday at ten.",
            keep: ["Dana", "Leo", "Priti", "20th"], notAdd: ["action", "agenda"],
            classes: [.lists, .numbers, .capitalisationAndTokens, .commas]),
        piece(
            .meetingMinutes, "board-review",
            "notes from the quarterly review. the budget came in at four hundred and twenty thousand which is eight percent under plan. hiring is paused until january apart from the two support roles. the board asked for a written risk register by the end of november. owen will circulate these notes and the slides tonight",
            "Notes from the quarterly review. The budget came in at 420,000, which is 8% under plan. Hiring is paused until January apart from the two support roles. The board asked for a written risk register by the end of November. Owen will circulate these notes and the slides tonight.",
            keep: ["420,000", "8%", "risk register"], notAdd: ["dollars", "approved"],
            classes: [.numbers, .commas, .capitalisationAndTokens]),
        piece(
            .meetingMinutes, "site-visit",
            "site visit summary. we walked the ground floor with the contractor at nine. the east wall still shows damp near the window frames. the electrician needs access on the twelfth and the thirteenth. the skip will be collected on monday. open question who signs off the kitchen layout before the cabinets are ordered",
            "Site visit summary. We walked the ground floor with the contractor at nine. The east wall still shows damp near the window frames. The electrician needs access on the 12th and the 13th. The skip will be collected on Monday. Open question, who signs off the kitchen layout before the cabinets are ordered?",
            keep: ["damp", "12th", "13th", "cabinets"], notAdd: ["builder", "urgent"],
            classes: [.numbers, .questions, .sentenceBoundaries]),
        piece(
            .statusReport, "weekly-update",
            "weekly update. the search rewrite is ninety percent done and the remaining work is pagination. p ninety five latency fell from eight hundred milliseconds to three hundred and ten. we found one blocker the staging database is still on version fourteen. next week i will finish pagination and pair with sam on the migration",
            "Weekly update. The search rewrite is 90% done and the remaining work is pagination. P95 latency fell from 800 milliseconds to 310. We found one blocker, the staging database is still on version 14. Next week I will finish pagination and pair with Sam on the migration.",
            keep: ["90%", "pagination", "310"], notAdd: ["ms", "risk"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .statusReport, "warehouse-status",
            "status for the warehouse move. eighty pallets are packed out of one hundred and twenty. the forklift hire is booked for the ninth to the eleventh. we are still waiting on the fire inspection for the new unit. if it slips past the fifth the move goes back a full week",
            "Status for the warehouse move. 80 pallets are packed out of 120. The forklift hire is booked for the 9th to the 11th. We are still waiting on the fire inspection for the new unit. If it slips past the 5th, the move goes back a full week.",
            keep: ["80", "120", "forklift", "inspection"], notAdd: ["delayed", "percent"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .statusReport, "grant-progress",
            "progress on the community garden grant. we have planted the first twelve raised beds and the water butt is installed. volunteer hours this month came to one hundred and sixty. spending so far is two thousand three hundred out of five thousand. the next milestone is the open day on the twenty eighth of april",
            "Progress on the community garden grant. We have planted the first 12 raised beds and the water butt is installed. Volunteer hours this month came to 160. Spending so far is 2,300 out of 5,000. The next milestone is the open day on the 28th of April.",
            keep: ["raised beds", "160", "28th of April"], notAdd: ["budget", "dollars"],
            classes: [.numbers, .sentenceBoundaries]),
        piece(
            .proposal, "shared-calendar",
            "proposal we move the team onto one shared calendar. today each person keeps their own and we double book the meeting room about twice a week. a shared calendar would show room bookings and leave in one place. the cost is nothing because we already pay for it. i suggest a two week trial starting on the first of march",
            "Proposal: we move the team onto one shared calendar. Today each person keeps their own and we double book the meeting room about twice a week. A shared calendar would show room bookings and leave in one place. The cost is nothing because we already pay for it. I suggest a two week trial starting on the 1st of March.",
            keep: ["shared calendar", "trial", "1st of March"], notAdd: ["free", "savings"],
            classes: [.sentenceBoundaries, .numbers, .quotesAndBrackets]),
        piece(
            .proposal, "bike-racks",
            "i would like to propose adding bike racks outside the north entrance. at the moment about thirty people lock bikes to the railings which blocks the ramp. a rack for forty bikes costs around one thousand five hundred dollars installed. the facilities team said it could be done in a single weekend",
            "I would like to propose adding bike racks outside the north entrance. At the moment about 30 people lock bikes to the railings, which blocks the ramp. A rack for 40 bikes costs around 1,500 dollars installed. The facilities team said it could be done in a single weekend.",
            keep: ["bike racks", "ramp", "1,500"], notAdd: ["safety", "approve"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .proposal, "four-day-pilot",
            "summary of the proposal. we pilot a four day week for the support team over three months. coverage stays at five days by staggering the day off. we measure first response time customer satisfaction and sick days against the same months last year. if response time rises by more than ten percent we stop the pilot early",
            "Summary of the proposal. We pilot a four day week for the support team over three months. Coverage stays at five days by staggering the day off. We measure first response time, customer satisfaction and sick days against the same months last year. If response time rises by more than 10%, we stop the pilot early.",
            keep: ["four day week", "staggering", "10%"], notAdd: ["wellbeing", "productivity"],
            classes: [.lists, .commas, .numbers]),
    ]

    static let everydayWriting: [EvaluationCase] = [
        piece(
            .invitation, "garden-party",
            "you are invited to our garden party on saturday the sixteenth of july from three until late. we will have a barbecue and a few games for the kids. bring a chair if you have one and something to drink. our address is fourteen willow lane and parking is on the street. please let us know by the tenth if you can come",
            "You are invited to our garden party on Saturday the 16th of July from three until late. We will have a barbecue and a few games for the kids. Bring a chair if you have one and something to drink. Our address is 14 Willow Lane and parking is on the street. Please let us know by the 10th if you can come.",
            keep: ["16th of July", "14 Willow Lane", "barbecue"], notAdd: ["RSVP", "food"],
            classes: [.numbers, .capitalisationAndTokens, .sentenceBoundaries]),
        piece(
            .invitation, "retirement-lunch",
            "please join us for a lunch to celebrate carol retiring after twenty six years with the library. it is on friday the third of may at twelve thirty at the riverside hall. there will be a short speech at one fifteen. we are collecting for a gift so if you would like to add something see ben at the front desk",
            "Please join us for a lunch to celebrate Carol retiring after 26 years with the library. It is on Friday the 3rd of May at 12:30 at the Riverside Hall. There will be a short speech at 1:15. We are collecting for a gift, so if you would like to add something, see Ben at the front desk.",
            keep: ["Carol", "26 years", "Ben"], notAdd: ["congratulations", "party"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .invitation, "study-group",
            "hey everyone we are starting a study group for the statistics module. we will meet every wednesday at six in room b twelve of the main building. the first session covers chapters one to three. bring the problem sheet and a calculator. message me if you want to join the group chat",
            "Hey everyone, we are starting a study group for the statistics module. We will meet every Wednesday at six in room B12 of the main building. The first session covers chapters 1 to 3. Bring the problem sheet and a calculator. Message me if you want to join the group chat.",
            keep: ["Wednesday", "B12", "calculator"], notAdd: ["exam", "maths"],
            classes: [.capitalisationAndTokens, .numbers, .commas]),
        piece(
            .shoppingList, "weekly-shop",
            "shopping list new line two litres of milk new line a dozen eggs new line wholemeal bread new line five hundred grams of rice new line spinach new line washing up liquid new line batteries double a new line a bag of oranges new line two tins of chopped tomatoes new line bin bags",
            "Shopping list\n2 litres of milk\nA dozen eggs\nWholemeal bread\n500 grams of rice\nSpinach\nWashing up liquid\nBatteries AA\nA bag of oranges\nTwo tins of chopped tomatoes\nBin bags",
            keep: ["milk", "eggs", "rice", "AA"], notAdd: ["cheese", "butter"],
            classes: [.lists, .numbers, .capitalisationAndTokens]),
        piece(
            .shoppingList, "party-supplies",
            "for the party we need forty paper plates thirty cups three bags of ice two packs of candles one large cake from the bakery on station road and some balloons. the cake needs to say happy tenth birthday maya in blue letters and it has to be collected by four",
            "For the party we need 40 paper plates, 30 cups, three bags of ice, two packs of candles, one large cake from the bakery on Station Road and some balloons. The cake needs to say happy 10th birthday Maya in blue letters, and it has to be collected by four.",
            keep: ["40", "30", "Station Road", "Maya"], notAdd: ["napkins", "decorations"],
            classes: [.lists, .commas, .numbers, .capitalisationAndTokens]),
        piece(
            .shoppingList, "hardware-run",
            "things to get from the hardware shop. a box of four by forty screws. wall plugs size six. a tin of white gloss paint. sandpaper grade one twenty. a new blade for the craft knife. and ask whether they stock the ten mill drill bit",
            "Things to get from the hardware shop. A box of 4 by 40 screws. Wall plugs size 6. A tin of white gloss paint. Sandpaper grade 120. A new blade for the craft knife. And ask whether they stock the 10 mm drill bit.",
            keep: ["screws", "120", "drill bit"], notAdd: ["hammer", "nails"],
            classes: [.lists, .numbers, .sentenceBoundaries]),
        piece(
            .recipe, "lentil-soup",
            "lentil soup for four. soften one chopped onion and two carrots in a tablespoon of oil for about ten minutes. add two hundred grams of red lentils one litre of stock and a teaspoon of cumin. simmer for twenty five minutes until the lentils break down. season with salt and a squeeze of lemon and blend if you like it smooth",
            "Lentil soup for four. Soften one chopped onion and two carrots in a tablespoon of oil for about 10 minutes. Add 200 grams of red lentils, one litre of stock and a teaspoon of cumin. Simmer for 25 minutes until the lentils break down. Season with salt and a squeeze of lemon, and blend if you like it smooth.",
            keep: ["200 grams", "cumin", "25 minutes"], notAdd: ["garlic", "pepper"],
            classes: [.numbers, .commas, .lists]),
        piece(
            .recipe, "flatbreads",
            "quick flatbreads. mix two hundred and fifty grams of flour with half a teaspoon of salt and one hundred and fifty grams of yoghurt. knead for two minutes then rest for fifteen. split into six balls and roll each one thin. cook in a dry pan on high heat for about a minute a side until they puff",
            "Quick flatbreads. Mix 250 grams of flour with half a teaspoon of salt and 150 grams of yoghurt. Knead for two minutes, then rest for 15. Split into six balls and roll each one thin. Cook in a dry pan on high heat for about a minute a side until they puff.",
            keep: ["250 grams", "yoghurt", "six balls"], notAdd: ["butter", "oven"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .recipe, "overnight-oats",
            "overnight oats. in a jar mix forty grams of oats one hundred millilitres of milk two spoons of yoghurt and a handful of berries. stir in a teaspoon of honey if you want it sweeter. close the lid and leave it in the fridge for at least six hours. it keeps for two days",
            "Overnight oats. In a jar, mix 40 grams of oats, 100 millilitres of milk, two spoons of yoghurt and a handful of berries. Stir in a teaspoon of honey if you want it sweeter. Close the lid and leave it in the fridge for at least six hours. It keeps for two days.",
            keep: ["40 grams", "berries", "fridge"], notAdd: ["sugar", "banana"],
            classes: [.numbers, .commas, .lists]),
        piece(
            .travelPlan, "rail-trip",
            "travel plan for the conference. train leaves at seven forty from platform four and arrives at eleven ten. the hotel is a ten minute walk and check in opens at three. the keynote starts at one so drop the bags at the desk first. return train is on thursday at five fifteen and the seats are in coach c",
            "Travel plan for the conference. Train leaves at 7:40 from platform 4 and arrives at 11:10. The hotel is a 10 minute walk and check in opens at three. The keynote starts at one, so drop the bags at the desk first. Return train is on Thursday at 5:15 and the seats are in coach C.",
            keep: ["7:40", "11:10", "coach C"], notAdd: ["taxi", "booked"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .travelPlan, "road-trip",
            "day one drive from the cabin to the coast which is about three hundred kilometres. stop for lunch at the lake around noon. day two is the ferry at nine fifteen so we need to leave the campsite by eight. day three we head inland and stay two nights at the farm. fuel up before the pass because there is nothing for sixty k",
            "Day one, drive from the cabin to the coast, which is about 300 kilometres. Stop for lunch at the lake around noon. Day two is the ferry at 9:15, so we need to leave the campsite by eight. Day three, we head inland and stay two nights at the farm. Fuel up before the pass because there is nothing for 60k.",
            keep: ["300 kilometres", "9:15", "60k"], notAdd: ["hotel", "petrol"],
            classes: [.lists, .numbers, .commas]),
        piece(
            .travelPlan, "city-weekend",
            "plan for the city weekend. friday evening check into the guest house on harbour street. saturday morning the museum opens at ten and tickets are eighteen euros. saturday afternoon the old town walking tour leaves from the clock tower at two. sunday we have brunch and catch the four o'clock bus home",
            "Plan for the city weekend. Friday evening, check into the guest house on Harbour Street. Saturday morning, the museum opens at ten and tickets are 18 euros. Saturday afternoon, the old town walking tour leaves from the clock tower at two. Sunday we have brunch and catch the four o'clock bus home.",
            keep: ["Harbour Street", "18 euros", "clock tower"], notAdd: ["hotel", "€"],
            classes: [.lists, .numbers, .capitalisationAndTokens, .commas]),
    ]

    static let formalWriting: [EvaluationCase] = [
        piece(
            .coverLetter, "library-assistant",
            "dear hiring team i am applying for the library assistant role advertised on your website. for the past three years i have run the after school reading club at a primary school where attendance grew from twelve to forty children. i am comfortable with cataloguing software and i enjoy helping people find what they need. new paragraph i would welcome the chance to talk further. yours sincerely ruth calloway",
            "Dear hiring team, I am applying for the library assistant role advertised on your website. For the past three years, I have run the after school reading club at a primary school, where attendance grew from 12 to 40 children. I am comfortable with cataloguing software and I enjoy helping people find what they need.\n\nI would welcome the chance to talk further. Yours sincerely, Ruth Calloway",
            keep: ["library assistant", "12", "40", "Ruth Calloway"], notAdd: ["passionate", "experience"],
            classes: [.paragraphs, .numbers, .capitalisationAndTokens, .commas]),
        piece(
            .coverLetter, "junior-analyst",
            "dear ms okafor i would like to be considered for the junior analyst position. in my final year i built a model that forecast weekly footfall for a local market to within six percent. i use sql and python every day and i have presented results to non technical audiences. i am available to start in september. thank you for your time. sincerely felix arden",
            "Dear Ms Okafor, I would like to be considered for the junior analyst position. In my final year, I built a model that forecast weekly footfall for a local market to within 6%. I use SQL and Python every day and I have presented results to non technical audiences. I am available to start in September. Thank you for your time. Sincerely, Felix Arden",
            keep: ["Okafor", "6%", "SQL", "Python", "Felix Arden"], notAdd: ["excited", "skills"],
            classes: [.capitalisationAndTokens, .numbers, .commas]),
        piece(
            .coverLetter, "chef-de-partie",
            "to the head chef i am writing about the chef de partie opening. i have spent four years on the pastry section of a hotel kitchen serving up to two hundred covers a night. i hold a level two food hygiene certificate and i am happy to work weekends. my references are attached. best regards noor haddad",
            "To the head chef, I am writing about the chef de partie opening. I have spent four years on the pastry section of a hotel kitchen serving up to 200 covers a night. I hold a level 2 food hygiene certificate and I am happy to work weekends. My references are attached. Best regards, Noor Haddad",
            keep: ["pastry", "200 covers", "Noor Haddad"], notAdd: ["dedicated", "restaurant"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .clinicNote, "knee-review",
            "follow up for left knee pain. patient reports pain three out of ten down from seven at the last visit. swelling has settled and range of movement is near full. continue ibuprofen four hundred milligrams three times a day with food for one more week then stop. review in four weeks or sooner if the knee locks",
            "Follow up for left knee pain. Patient reports pain 3/10, down from 7 at the last visit. Swelling has settled and range of movement is near full. Continue ibuprofen 400 mg three times a day with food for one more week, then stop. Review in four weeks or sooner if the knee locks.",
            keep: ["ibuprofen", "400 mg", "four weeks"], notAdd: ["paracetamol", "MRI"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .clinicNote, "blood-pressure",
            "blood pressure check today one thirty eight over eighty six. home readings over the past fortnight average one forty two over eighty eight. no headaches or dizziness. start amlodipine five milligrams once daily. advised less salt and a thirty minute walk most days. repeat bloods and review in six weeks",
            "Blood pressure check today 138/86. Home readings over the past fortnight average 142/88. No headaches or dizziness. Start amlodipine 5 mg once daily. Advised less salt and a 30 minute walk most days. Repeat bloods and review in six weeks.",
            keep: ["138/86", "142/88", "amlodipine", "5 mg"], notAdd: ["hypertension", "diet"],
            classes: [.numbers, .capitalisationAndTokens, .sentenceBoundaries]),
        piece(
            .clinicNote, "child-fever",
            "four year old with fever for two days highest temperature thirty nine point one. eating less but drinking well and passing urine normally. chest clear ears slightly red on the right. advised paracetamol by weight and plenty of fluids. return if the fever lasts beyond five days or a rash appears",
            "4 year old with fever for two days, highest temperature 39.1. Eating less but drinking well and passing urine normally. Chest clear, ears slightly red on the right. Advised paracetamol by weight and plenty of fluids. Return if the fever lasts beyond five days or a rash appears.",
            keep: ["39.1", "paracetamol", "rash"], notAdd: ["antibiotics", "infection"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .legalClause, "termination",
            "clause nine termination. either party may end this agreement by giving thirty days written notice to the other party. the supplier may end it immediately if any invoice remains unpaid for more than sixty days after its due date. ending the agreement does not affect any rights that arose before the date it ends",
            "Clause 9, termination. Either party may end this agreement by giving 30 days written notice to the other party. The supplier may end it immediately if any invoice remains unpaid for more than 60 days after its due date. Ending the agreement does not affect any rights that arose before the date it ends.",
            keep: ["30 days", "60 days", "supplier"], notAdd: ["shall", "hereby"],
            classes: [.numbers, .capitalisationAndTokens, .sentenceBoundaries]),
        piece(
            .legalClause, "deposit",
            "the tenant will pay a deposit of one thousand two hundred pounds before the start of the tenancy. the landlord will protect the deposit in an approved scheme within thirty days. the deposit will be returned within ten days of the end of the tenancy less any agreed deductions for damage beyond fair wear and tear",
            "The tenant will pay a deposit of 1,200 pounds before the start of the tenancy. The landlord will protect the deposit in an approved scheme within 30 days. The deposit will be returned within 10 days of the end of the tenancy, less any agreed deductions for damage beyond fair wear and tear.",
            keep: ["1,200 pounds", "30 days", "wear and tear"], notAdd: ["£", "rent"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .legalClause, "confidentiality",
            "section four point two confidentiality. each party will keep the other party's confidential information secret and will use it only to perform this agreement. this duty does not apply to information that is already public or that a court orders to be disclosed. this section continues for three years after the agreement ends",
            "Section 4.2, confidentiality. Each party will keep the other party's confidential information secret and will use it only to perform this agreement. This duty does not apply to information that is already public or that a court orders to be disclosed. This section continues for three years after the agreement ends.",
            keep: ["4.2", "court", "three years"], notAdd: ["shall", "proprietary"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
    ]

    static let creativeWriting: [EvaluationCase] = [
        piece(
            .essayParagraph, "public-libraries",
            "public libraries are often described as quiet places but the busiest branch in our town is anything but quiet. on a weekday afternoon it hosts a homework club a job search session and a toddler rhyme time all at once. the building has become the town's living room. if we judge libraries only by how many books they lend we miss most of what they do",
            "Public libraries are often described as quiet places, but the busiest branch in our town is anything but quiet. On a weekday afternoon, it hosts a homework club, a job search session and a toddler rhyme time all at once. The building has become the town's living room. If we judge libraries only by how many books they lend, we miss most of what they do.",
            keep: ["libraries", "rhyme time", "living room"], notAdd: ["community", "however"],
            classes: [.commas, .sentenceBoundaries]),
        piece(
            .essayParagraph, "night-trains",
            "the night train is slower than a flight but it gives back something a flight takes away. you board in one city after dinner and wake up in another with the whole evening and the morning still yours. there is no queue at security and no transfer from an airport an hour outside town. for trips under a thousand kilometres the real comparison is door to door time and on that measure the train often wins",
            "The night train is slower than a flight, but it gives back something a flight takes away. You board in one city after dinner and wake up in another with the whole evening and the morning still yours. There is no queue at security and no transfer from an airport an hour outside town. For trips under 1,000 kilometres, the real comparison is door to door time, and on that measure the train often wins.",
            keep: ["night train", "1,000 kilometres", "door to door"], notAdd: ["cheaper", "emissions"],
            classes: [.commas, .numbers, .sentenceBoundaries]),
        piece(
            .essayParagraph, "handwriting",
            "some schools have stopped teaching joined up handwriting and it is easy to see why. most writing now happens on a keyboard. yet studies of note taking suggest that writing by hand forces us to summarise rather than copy. the question is not whether children will need pens at work but whether the act of writing slowly still teaches them to think",
            "Some schools have stopped teaching joined up handwriting, and it is easy to see why. Most writing now happens on a keyboard. Yet studies of note taking suggest that writing by hand forces us to summarise rather than copy. The question is not whether children will need pens at work, but whether the act of writing slowly still teaches them to think.",
            keep: ["handwriting", "summarise", "think"], notAdd: ["research", "therefore"],
            classes: [.commas, .sentenceBoundaries]),
        piece(
            .poem, "harbour-morning",
            "new line the harbour wakes before the town new line gulls argue over yesterday new line a single boat goes out alone new line and leaves a long white line behind new line the water folds it slowly down new line as if it never went away",
            "The harbour wakes before the town\nGulls argue over yesterday\nA single boat goes out alone\nAnd leaves a long white line behind\nThe water folds it slowly down\nAs if it never went away",
            keep: ["harbour", "gulls", "white line"], notAdd: ["sea", "ocean"],
            classes: [.paragraphs, .capitalisationAndTokens], context: emptyField),
        piece(
            .poem, "winter-list",
            "four things for winter new line a kettle singing on the stove new line a scarf that smells of someone else new line the first frost writing on the glass new line and one more hour of dark than light new line until the spring comes back again",
            "Four things for winter\nA kettle singing on the stove\nA scarf that smells of someone else\nThe first frost writing on the glass\nAnd one more hour of dark than light\nUntil the spring comes back again",
            keep: ["kettle", "scarf", "frost"], notAdd: ["snow", "cold"],
            classes: [.paragraphs, .lists, .capitalisationAndTokens]),
        piece(
            .poem, "station-clock",
            "the station clock is always right new line it does not care if you are late new line it does not wait it does not wave new line it only counts the minutes down new line to trains that leave without a word",
            "The station clock is always right\nIt does not care if you are late\nIt does not wait, it does not wave\nIt only counts the minutes down\nTo trains that leave without a word",
            keep: ["station clock", "minutes", "trains"], notAdd: ["time", "platform"],
            classes: [.paragraphs, .commas]),
        piece(
            .productDescription, "desk-lamp",
            "the arc desk lamp has a weighted steel base and an arm that folds flat for storage. the warm white led gives four hundred lumens at full brightness and dims in five steps. it charges over usb c and runs for about eight hours on one charge. available in sage grey and sand. two year warranty",
            "The Arc desk lamp has a weighted steel base and an arm that folds flat for storage. The warm white LED gives 400 lumens at full brightness and dims in five steps. It charges over USB-C and runs for about eight hours on one charge. Available in sage, grey and sand. Two year warranty.",
            keep: ["LED", "400 lumens", "USB-C", "warranty"], notAdd: ["stylish", "premium"],
            classes: [.capitalisationAndTokens, .numbers, .lists, .commas]),
        piece(
            .productDescription, "rain-jacket",
            "a lightweight rain jacket for walking and cycling. the shell weighs three hundred and twenty grams and packs into its own chest pocket. taped seams and a ten thousand millimetre waterproof rating keep it dry in steady rain. the hood adjusts at the back and fits over a helmet. machine wash at thirty degrees",
            "A lightweight rain jacket for walking and cycling. The shell weighs 320 grams and packs into its own chest pocket. Taped seams and a 10,000 mm waterproof rating keep it dry in steady rain. The hood adjusts at the back and fits over a helmet. Machine wash at 30 degrees.",
            keep: ["320 grams", "10,000 mm", "helmet"], notAdd: ["breathable", "durable"],
            classes: [.numbers, .capitalisationAndTokens, .sentenceBoundaries]),
        piece(
            .productDescription, "tea-sampler",
            "the tea sampler holds six loose leaf teas in resealable tins of fifty grams each. you get two black teas two green teas a rooibos and a mint blend. each tin makes about twenty cups. brewing notes are printed on the lid. ships in a recycled card box",
            "The tea sampler holds six loose leaf teas in resealable tins of 50 grams each. You get two black teas, two green teas, a rooibos and a mint blend. Each tin makes about 20 cups. Brewing notes are printed on the lid. Ships in a recycled card box.",
            keep: ["50 grams", "rooibos", "20 cups"], notAdd: ["organic", "gift"],
            classes: [.numbers, .lists, .commas]),
    ]

    static let mixedSpeech: [EvaluationCase] = [
        piece(
            .socialPost, "marathon",
            "finished my first half marathon today in two hours four minutes. the last three k were brutal but the crowd on the bridge carried me home. huge thanks to the running club for the training plan. hashtag half marathon hashtag first race",
            "Finished my first half marathon today in 2 hours 4 minutes. The last 3k were brutal, but the crowd on the bridge carried me home. Huge thanks to the running club for the training plan. #halfmarathon #firstrace",
            keep: ["half marathon", "3k", "#halfmarathon", "#firstrace"], notAdd: ["proud", "kilometres"],
            classes: [.numbers, .capitalisationAndTokens, .codeAndMarkdown]),
        piece(
            .socialPost, "bakery-opening",
            "big news the bakery on corner street opens its doors this saturday at eight. first fifty customers get a free cinnamon bun. come say hello and tag us at corner bakes so we can share your photos. see you there and bring a friend",
            "Big news, the bakery on Corner Street opens its doors this Saturday at eight. First 50 customers get a free cinnamon bun. Come say hello and tag us @cornerbakes so we can share your photos. See you there and bring a friend.",
            keep: ["Corner Street", "50", "@cornerbakes"], notAdd: ["discount", "coffee"],
            classes: [.capitalisationAndTokens, .numbers, .codeAndMarkdown]),
        piece(
            .socialPost, "volunteer-call",
            "we need volunteers for the beach clean up on sunday the ninth from ten to one. gloves and bags are provided just bring water and sun cream. last time we cleared ninety kilos of rubbish in three hours. sign up at example dot org slash clean up",
            "We need volunteers for the beach clean up on Sunday the 9th from ten to one. Gloves and bags are provided, just bring water and sun cream. Last time we cleared 90 kilos of rubbish in three hours. Sign up at example.org/cleanup.",
            keep: ["9th", "90 kilos", "example.org/cleanup"], notAdd: ["plastic", "community"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .announcement, "office-closure",
            "announcement the office will be closed on monday the twenty sixth for the public holiday. the help desk phone line will still be staffed from nine until five. if you need building access that day email facilities at example dot com by thursday. normal hours resume on tuesday",
            "Announcement: the office will be closed on Monday the 26th for the public holiday. The help desk phone line will still be staffed from nine until five. If you need building access that day, email facilities@example.com by Thursday. Normal hours resume on Tuesday.",
            keep: ["26th", "facilities@example.com", "Tuesday"], notAdd: ["holiday season", "closed until"],
            classes: [.numbers, .capitalisationAndTokens, .commas]),
        piece(
            .announcement, "pool-maintenance",
            "attention swimmers the main pool will close from the first to the fourteenth of february for tile repairs. the learner pool stays open with lanes from six thirty until nine in the morning. memberships will be extended by two weeks at no cost. we are sorry for the disruption",
            "Attention swimmers, the main pool will close from the 1st to the 14th of February for tile repairs. The learner pool stays open with lanes from 6:30 until nine in the morning. Memberships will be extended by two weeks at no cost. We are sorry for the disruption.",
            keep: ["14th of February", "6:30", "two weeks"], notAdd: ["refund", "apologise"],
            classes: [.numbers, .commas, .sentenceBoundaries]),
        piece(
            .announcement, "new-starter",
            "please welcome tamsin hale who joins the design team today as a senior designer. tamsin spent five years designing transport maps and will lead the wayfinding work for the new site. her desk is on the third floor next to the print room. say hello when you get the chance",
            "Please welcome Tamsin Hale, who joins the design team today as a senior designer. Tamsin spent five years designing transport maps and will lead the wayfinding work for the new site. Her desk is on the third floor next to the print room. Say hello when you get the chance.",
            keep: ["Tamsin Hale", "wayfinding", "third floor"], notAdd: ["excited", "talented"],
            classes: [.capitalisationAndTokens, .commas, .sentenceBoundaries]),
        piece(
            .correctedReply, "meeting-time",
            "sure let us meet on tuesday at three no sorry four because i have the dentist before. we can use the small room on the second floor. actually make that the cafe downstairs the small room is booked. i will bring the printed draft",
            "Sure, let us meet on Tuesday at four because I have the dentist before. We can use the cafe downstairs, the small room is booked. I will bring the printed draft.",
            keep: ["Tuesday", "four", "dentist", "draft"], notAdd: ["three", "second floor"],
            classes: [.corrections, .commas, .sentenceBoundaries]),
        piece(
            .correctedReply, "order-quantity",
            "please order twenty no make it thirty boxes of the a four paper and two of the a three. delivery to the main office on wednesday i mean thursday wednesday is the stocktake. put it on the account ending four four one",
            "Please order 30 boxes of the A4 paper and two of the A3. Delivery to the main office on Thursday, Wednesday is the stocktake. Put it on the account ending 441.",
            keep: ["30", "A4", "A3", "Thursday", "441"], notAdd: ["20 boxes", "twenty"],
            classes: [.corrections, .numbers, .capitalisationAndTokens]),
        piece(
            .correctedReply, "address-fix",
            "the parcel should go to twelve elm road sorry twenty one elm road the flat above the shop. the postcode is the same. call me when you are outside and i will come down. if nobody answers leave it with the shop",
            "The parcel should go to 21 Elm Road, the flat above the shop. The postcode is the same. Call me when you are outside and I will come down. If nobody answers, leave it with the shop.",
            keep: ["21 Elm Road", "postcode", "shop"], notAdd: ["12 Elm Road", "twelve"],
            classes: [.corrections, .numbers, .capitalisationAndTokens]),
        piece(
            .hinglishTechnical, "deploy-update",
            "bhai deploy ho gaya hai staging pe. bas ek issue hai the api is returning five hundred for the login endpoint. logs mein dekha toh database connection timeout aa raha hai. main config check karke batata hoon kal tak fix ho jayega",
            "Bhai, deploy ho gaya hai staging pe. Bas ek issue hai, the API is returning 500 for the login endpoint. Logs mein dekha toh database connection timeout aa raha hai. Main config check karke batata hoon, kal tak fix ho jayega.",
            keep: ["deploy", "staging", "API", "500", "timeout"], notAdd: ["brother", "server"],
            classes: [.hinglish, .capitalisationAndTokens, .numbers], category: .multilingual),
        piece(
            .hinglishTechnical, "review-feedback",
            "pr dekh liya maine. code theek hai but tests missing hain for the retry logic. ek baar null case bhi handle kar do warna crash ho sakta hai. merge karne se pehle ci green hona chahiye. aur readme mein naya flag bhi document kar dena please",
            "PR dekh liya maine. Code theek hai but tests missing hain for the retry logic. Ek baar null case bhi handle kar do, warna crash ho sakta hai. Merge karne se pehle CI green hona chahiye. Aur README mein naya flag bhi document kar dena please.",
            keep: ["PR", "retry", "null", "CI"], notAdd: ["review", "approved"],
            classes: [.hinglish, .capitalisationAndTokens, .commas], category: .multilingual),
        piece(
            .hinglishTechnical, "sprint-plan",
            "is sprint mein teen kaam hain. pehla search ka pagination. doosra payment page ka redesign. teesra android app mein dark mode. estimate total twenty points ka hai aur deadline pandrah tareekh hai. agar pagination late hua toh dark mode next sprint mein shift kar denge",
            "Is sprint mein teen kaam hain. Pehla search ka pagination. Doosra payment page ka redesign. Teesra Android app mein dark mode. Estimate total 20 points ka hai aur deadline pandrah tareekh hai. Agar pagination late hua toh dark mode next sprint mein shift kar denge.",
            keep: ["sprint", "pagination", "Android", "pandrah"], notAdd: ["three", "fifteenth"],
            classes: [.hinglish, .lists, .capitalisationAndTokens], category: .multilingual),
    ]
}
