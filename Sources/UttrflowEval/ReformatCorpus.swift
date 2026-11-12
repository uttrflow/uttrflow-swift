// Last dictations for the reformat commands, with the text each must write. See `Docs/commands.md`.
import UttrflowCore

/// One last dictation, the reformat said over it, and the text that must replace it.
struct ReformatCase: Sendable, Equatable {
    /// The `spoken-commands.json` row said under the command key.
    let commandID: String
    /// Where the dictation stands, which decides whether a list is laid out there.
    let destination: Destination
    /// The last dictation as the field holds it.
    let text: String
    /// What the command writes in its place; nil when it must refuse and write nothing.
    let expected: String?
}

extension EvaluationCorpus {
    /// 30 cases per reformat row: runs that change only case or layout, and refusals that write nothing.
    static let reformatCases: [ReformatCase] = [
        reformat("reformat.sentence", .document, "meet me at five", "Meet me at five"),
        reformat("reformat.sentence", .document, "meet me at five.", "Meet me at five."),
        reformat(
            "reformat.sentence", .document, "send the report today. then call the client.",
            "Send the report today. Then call the client."),
        reformat("reformat.sentence", .document, "i think we should wait", "I think we should wait"),
        reformat(
            "reformat.sentence", .document, "the build passed. i will ship it tomorrow.",
            "The build passed. I will ship it tomorrow."),
        reformat("reformat.sentence", .document, "thanks for the update", "Thanks for the update"),
        reformat("reformat.sentence", .document, "ok see you there", "Ok see you there"),
        reformat(
            "reformat.sentence", .document, "is the room free on friday?", "Is the room free on friday?"),
        reformat(
            "reformat.sentence", .document, "call me back. it is urgent!", "Call me back. It is urgent!"),
        reformat("reformat.sentence", .document, "and then we left", "And then we left"),
        reformat(
            "reformat.sentence", .document, "please review the draft before noon",
            "Please review the draft before noon"),
        reformat("reformat.sentence", .document, "we met Priya at the office", "We met Priya at the office"),
        reformat("reformat.sentence", .document, "the API returns JSON", "The API returns JSON"),
        reformat(
            "reformat.sentence", .document, "check the logs. restart the server. tell the team.",
            "Check the logs. Restart the server. Tell the team."),
        reformat("reformat.sentence", .document, "Meet me at five.", nil),
        reformat("reformat.sentence", .document, "Thanks for the update.", nil),
        reformat("reformat.sentence", .document, "lunch is at one", "Lunch is at one"),
        reformat(
            "reformat.sentence", .document, "the train leaves at nine. do not be late.",
            "The train leaves at nine. Do not be late."),
        reformat("reformat.sentence", .document, "first draft attached", "First draft attached"),
        reformat("reformat.sentence", .document, "see notes below", "See notes below"),
        reformat("reformat.sentence", .document, "remember to buy milk", "Remember to buy milk"),
        reformat(
            "reformat.sentence", .document, "we should book the hall\nthe caterer is confirmed",
            "We should book the hall\nThe caterer is confirmed"),
        reformat("reformat.sentence", .document, "- milk\n- eggs", "- Milk\n- Eggs"),
        reformat("reformat.sentence", .document, "good morning everyone", "Good morning everyone"),
        reformat(
            "reformat.sentence", .document, "the meeting moved to tuesday", "The meeting moved to tuesday"),
        reformat("reformat.sentence", .document, "why not try again", "Why not try again"),
        reformat(
            "reformat.sentence", .document, "this is fine. this is also fine.",
            "This is fine. This is also fine."),
        reformat("reformat.sentence", .document, "never mind", "Never mind"),
        reformat(
            "reformat.sentence", .document, "the parcel arrived yesterday", "The parcel arrived yesterday"),
        reformat("reformat.sentence", .document, "All good here.", nil),
        reformat("reformat.upper", .document, "meet me at five", "MEET ME AT FIVE"),
        reformat("reformat.upper", .document, "Meet me at five.", "MEET ME AT FIVE."),
        reformat(
            "reformat.upper", .document, "Send the report today. Then call the client.",
            "SEND THE REPORT TODAY. THEN CALL THE CLIENT."),
        reformat("reformat.upper", .messaging, "do not touch", "DO NOT TOUCH"),
        reformat("reformat.upper", .document, "the server is down", "THE SERVER IS DOWN"),
        reformat("reformat.upper", .document, "I need this by noon!", "I NEED THIS BY NOON!"),
        reformat("reformat.upper", .document, "Wet floor.", "WET FLOOR."),
        reformat("reformat.upper", .messaging, "please reply", "PLEASE REPLY"),
        reformat("reformat.upper", .document, "Closed on Monday.", "CLOSED ON MONDAY."),
        reformat("reformat.upper", .document, "the door code changed", "THE DOOR CODE CHANGED"),
        reformat("reformat.upper", .document, "Read this first.", "READ THIS FIRST."),
        reformat("reformat.upper", .messaging, "stop the deploy", "STOP THE DEPLOY"),
        reformat("reformat.upper", .document, "it's not ready", "IT'S NOT READY"),
        reformat("reformat.upper", .document, "Priya's laptop is here.", "PRIYA'S LAPTOP IS HERE."),
        reformat(
            "reformat.upper", .document, "Check the logs.\nRestart the server.",
            "CHECK THE LOGS.\nRESTART THE SERVER."),
        reformat("reformat.upper", .messaging, "- milk\n- eggs", "- MILK\n- EGGS"),
        reformat("reformat.upper", .document, "no parking", "NO PARKING"),
        reformat("reformat.upper", .document, "this is important", "THIS IS IMPORTANT"),
        reformat("reformat.upper", .document, "Call me back. It is urgent.", "CALL ME BACK. IT IS URGENT."),
        reformat("reformat.upper", .messaging, "do not reply all", "DO NOT REPLY ALL"),
        reformat("reformat.upper", .document, "Keep out.", "KEEP OUT."),
        reformat("reformat.upper", .document, "back in five minutes", "BACK IN FIVE MINUTES"),
        reformat("reformat.upper", .document, "Final notice.", "FINAL NOTICE."),
        reformat("reformat.upper", .messaging, "the build is red", "THE BUILD IS RED"),
        reformat("reformat.upper", .document, "Happy birthday!", "HAPPY BIRTHDAY!"),
        reformat("reformat.upper", .document, "see you at 3", "SEE YOU AT 3"),
        reformat("reformat.upper", .document, "use the side door", "USE THE SIDE DOOR"),
        reformat("reformat.upper", .messaging, "MEET ME AT FIVE.", nil),
        reformat("reformat.upper", .document, "URGENT", nil),
        reformat("reformat.upper", .document, "Do not enter.", "DO NOT ENTER."),
        reformat(
            "reformat.list", .document, "Buy milk. Call the plumber. Book the hall.",
            "- Buy milk.\n- Call the plumber.\n- Book the hall."),
        reformat(
            "reformat.list", .email, "Send the report. Call the client.",
            "- Send the report.\n- Call the client."),
        reformat(
            "reformat.list", .plain, "Check the logs. Restart the server. Tell the team.",
            "- Check the logs.\n- Restart the server.\n- Tell the team."),
        reformat("reformat.list", .document, "Milk\nEggs\nBread", "- Milk\n- Eggs\n- Bread"),
        reformat(
            "reformat.list", .email, "Pack the tent.\nPack the stove.", "- Pack the tent.\n- Pack the stove."),
        reformat(
            "reformat.list", .plain, "First we test. Then we ship.", "- First we test.\n- Then we ship."),
        reformat(
            "reformat.list", .document, "Book flights. Reserve the hotel. Rent a car. Pack.",
            "- Book flights.\n- Reserve the hotel.\n- Rent a car.\n- Pack."),
        reformat(
            "reformat.list", .email, "Review the draft. Fix the typos.",
            "- Review the draft.\n- Fix the typos."),
        reformat(
            "reformat.list", .plain, "Water the plants. Feed the cat.", "- Water the plants.\n- Feed the cat."
        ),
        reformat("reformat.list", .document, "Is it ready? Can we ship?", "- Is it ready?\n- Can we ship?"),
        reformat(
            "reformat.list", .email, "Call me. Text me. Email me.", "- Call me.\n- Text me.\n- Email me."),
        reformat(
            "reformat.list", .plain, "The room is booked.\n\nThe caterer is confirmed.",
            "- The room is booked.\n- The caterer is confirmed."),
        reformat(
            "reformat.list", .document, "Clean the desk. File the papers.",
            "- Clean the desk.\n- File the papers."),
        reformat(
            "reformat.list", .email, "Update the docs. Tag the release. Tell the team.",
            "- Update the docs.\n- Tag the release.\n- Tell the team."),
        reformat("reformat.list", .plain, "Wake up. Stretch. Run.", "- Wake up.\n- Stretch.\n- Run."),
        reformat(
            "reformat.list", .document, "Order lunch. Set up the room.", "- Order lunch.\n- Set up the room."),
        reformat(
            "reformat.list", .email, "Lock the door. Turn off the lights.",
            "- Lock the door.\n- Turn off the lights."),
        reformat(
            "reformat.list", .plain, "Read chapter one. Answer the questions.",
            "- Read chapter one.\n- Answer the questions."),
        reformat(
            "reformat.list", .document, "Pay rent. Pay the phone bill.", "- Pay rent.\n- Pay the phone bill."),
        reformat(
            "reformat.list", .email, "Fix the login bug. Ship the patch.",
            "- Fix the login bug.\n- Ship the patch."),
        reformat("reformat.list", .plain, "Buy milk, eggs and bread.", nil),
        reformat("reformat.list", .document, "Meet me at five.", nil),
        reformat("reformat.list", .email, "the server is down", nil),
        reformat("reformat.list", .plain, "Thanks for the update.", nil),
        reformat("reformat.list", .document, "- Milk\n- Eggs", nil),
        reformat("reformat.list", .messaging, "Buy milk. Call the plumber.", nil),
        reformat("reformat.list", .terminal, "Buy milk. Call the plumber.", nil),
        reformat("reformat.list", .codeEditor, "Buy milk. Call the plumber.", nil),
        reformat("reformat.list", .spreadsheet, "Buy milk. Call the plumber.", nil),
        reformat("reformat.list", .sqlEditor, "Buy milk. Call the plumber.", nil),
        reformat(
            "reformat.paragraph", .document, "The room is booked.\n\nThe caterer is confirmed.",
            "The room is booked. The caterer is confirmed."),
        reformat("reformat.paragraph", .document, "Line one.\nLine two.", "Line one. Line two."),
        reformat("reformat.paragraph", .document, "- Milk\n- Eggs\n- Bread", "Milk, Eggs, Bread"),
        reformat(
            "reformat.paragraph", .document, "Dear team,\n\nThe release is out.",
            "Dear team, The release is out."),
        reformat(
            "reformat.paragraph", .document, "First point.\n\nSecond point.\n\nThird point.",
            "First point. Second point. Third point."),
        reformat("reformat.paragraph", .document, "Milk\nEggs", "Milk, Eggs"),
        reformat(
            "reformat.paragraph", .document, "Check the logs.\nRestart the server.",
            "Check the logs. Restart the server."),
        reformat(
            "reformat.paragraph", .document, "1. Pack the tent\n2. Pack the stove",
            "Pack the tent, Pack the stove"),
        reformat("reformat.paragraph", .document, "Hi\nHow are you?", "Hi, How are you?"),
        reformat(
            "reformat.paragraph", .document, "The build passed.\nShip it.", "The build passed. Ship it."),
        reformat(
            "reformat.paragraph", .document, "We met today.\n\nWe agreed on a plan.",
            "We met today. We agreed on a plan."),
        reformat(
            "reformat.paragraph", .document, "- Call the client\n- Send the report",
            "Call the client, Send the report"),
        reformat("reformat.paragraph", .document, "Notes\nBring a pen", "Notes, Bring a pen"),
        reformat("reformat.paragraph", .document, "One.\nTwo.\nThree.", "One. Two. Three."),
        reformat(
            "reformat.paragraph", .document, "The office is closed.\n\nParking is free.",
            "The office is closed. Parking is free."),
        reformat("reformat.paragraph", .document, "Yes.\nNo.", "Yes. No."),
        reformat("reformat.paragraph", .document, "Thanks!\n\nSee you soon.", "Thanks! See you soon."),
        reformat("reformat.paragraph", .document, "Agenda:\n- budget\n- hiring", "Agenda, budget, hiring"),
        reformat(
            "reformat.paragraph", .document, "Good morning.\nThe train is late.",
            "Good morning. The train is late."),
        reformat("reformat.paragraph", .document, "Step one.\n\nStep two.", "Step one. Step two."),
        reformat(
            "reformat.paragraph", .document, "Morning all\nStandup is moved", "Morning all, Standup is moved"),
        reformat("reformat.paragraph", .document, "Pack.\nGo.", "Pack. Go."),
        reformat(
            "reformat.paragraph", .document, "The draft is ready.\nPlease review it.",
            "The draft is ready. Please review it."),
        reformat(
            "reformat.paragraph", .document, "Lunch at one.\n\nMeeting at two.",
            "Lunch at one. Meeting at two."),
        reformat("reformat.paragraph", .document, "Meet me at five.", nil),
        reformat("reformat.paragraph", .document, "One paragraph only.", nil),
        reformat("reformat.paragraph", .document, "the server is down", nil),
        reformat("reformat.paragraph", .document, "Buy milk, eggs and bread.", nil),
        reformat("reformat.paragraph", .document, "Thanks.", nil),
        reformat("reformat.paragraph", .document, "All good here.", nil),
    ]

    private static func reformat(
        _ commandID: String, _ destination: Destination, _ text: String, _ expected: String?
    ) -> ReformatCase {
        ReformatCase(commandID: commandID, destination: destination, text: text, expected: expected)
    }
}
