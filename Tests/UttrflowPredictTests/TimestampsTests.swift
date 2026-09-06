import Testing

@testable import UttrflowPredict

@Suite("Telling a timestamp from a message")
struct TimestampsTests {
    @Test("A message's timestamp parts are dropped, glued or spaced, in the calendar's own words.")
    func stampsAreDropped() {
        #expect(
            Timestamps.without("message, Meeting mei ho?, 3Septemberat6:38\u{202F}PM, Received from Priya")
                == "message, Meeting mei ho?, Received from Priya")
        #expect(
            Timestamps.without("Priya, Dear Customer, call me, 12:46 PM") == "Priya, Dear Customer, call me")
        #expect(Timestamps.without("Wed, 1 Jul at 12:46 PM") == "Wed")
        #expect(Timestamps.without("Photo, 5 Jul, Sent") == "Photo, Sent")
    }

    @Test("A time inside a message, a number, a tag and a bare 'at 5' are messages and stay.")
    func messagesStay() {
        #expect(Timestamps.without("Reached at 11:13 am today, ok") == "Reached at 11:13 am today, ok")
        #expect(Timestamps.without("see you at 7") == "see you at 7")
        #expect(Timestamps.without("Room 404, did #61") == "Room 404, did #61")
        #expect(!Timestamps.isTimestamp("at 5"))
        #expect(!Timestamps.isTimestamp("2026"))
        #expect(!Timestamps.isTimestamp("release"))
    }

    @Test("A bare time is a stamp even without a word, and a date is one once it names a month or a day.")
    func timesAndDatesAreStamps() {
        #expect(Timestamps.isTimestamp("10:30"))
        #expect(Timestamps.isTimestamp("Yesterday 4:14 PM"))
        #expect(Timestamps.isTimestamp("Tue, 7 Jul at 9:19 AM".dropFirst(5)))
        #expect(Timestamps.hasTime("at 6:41 PM"))
        #expect(!Timestamps.hasTime("6:4"))
        #expect(!Timestamps.hasTime(":123"))
    }
}
