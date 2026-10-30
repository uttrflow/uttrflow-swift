import Testing
@testable import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken letter beside a number in the shipped pipeline")
struct SpelledCodeDesignatorTests {
    @Test(
        "joins a letter and a number into one token where a designator or a known code is the evidence",
        arguments: [
            ("q three revenue was flat", "Q3 revenue was flat."),
            ("we beat q one", "We beat Q1."),
            ("the q four plan", "The Q4 plan."),
            ("h one numbers are in", "H1 numbers are in."),
            ("it is p zero now", "It is P0 now."),
            ("file it as p two", "File it as P2."),
            ("watch it in four k", "Watch it in 4K."),
            ("print it in three d", "Print it in 3D."),
            ("take vitamin b twelve daily", "Take vitamin B12 daily."),
            ("s p o two is ninety eight", "SpO2 is 98."),
            ("her s p o two is low", "Her SpO2 is low."),
            ("s p o two ninety eight percent on room air", "SpO2 98% on room air."),
            ("apartment twelve b", "Apartment 12B."),
            ("i live in flat four c", "I live in flat 4C."),
            ("go to gate b twelve", "Go to gate B12."),
            ("board at gate c three", "Board at gate C3."),
            ("take seat fourteen c", "Take seat 14C."),
            ("sit in seat b seven a", "Sit in seat B7A."),
            ("sit in seat twenty two a", "Sit in seat 22A."),
            ("we are in row f", "We are in row f."),
            ("meet in room b two", "Meet in room B2."),
            ("it is in suite three a", "It is in suite 3A."),
            ("land at terminal two b", "Land at terminal 2B."),
            ("i take flight u a four seven two", "I take flight UA 472."),
            ("book flight d l one eight two", "Book flight DL 182."),
            ("the flight b a two eight three", "The flight BA 283."),
            ("go with plan b two", "Go with plan B2."),
            ("it is priority p one", "It is priority P1."),
            ("get size two x l", "Get size 2XL."),
            ("order size m", "Order size m."),
            ("it is quarter q two", "It is quarter Q2."),
            ("use paper size a four", "Use paper size a 4."),
            ("room twelve b, then left", "Room 12B, then left."),
            ("gate b twelve.", "Gate B12."),
            ("go to row twelve c", "Go to row 12C."),
            ("the code is b one", "The code is b 1."),
            ("retries when uploading to s three", "Retries when uploading to S3."),
            ("so v one fails but the v two route works", "So v1 fails but the v2 route works."),
            ("the a four paper and two of the a three", "The A4 paper and 2 of the A3."),
            ("print these a five sheets", "Print these A5 sheets."),
        ])
    func joins(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves the article, a pronoun and a letter with no evidence as spoken",
        arguments: [
            ("a three bedroom flat", "A 3 bedroom flat."),
            ("a four week plan", "A 4 week plan."),
            ("a four hour delay", "A 4 hour delay."),
            ("we need plan b", "We need plan b."),
            ("take vitamin c", "Take vitamin c."),
            ("i have two", "I have 2."),
            ("q five is not a quarter", "Q 5 is not a quarter."),
            ("p nine is not a priority", "P 9 is not a priority."),
            ("give me a two minute warning", "Give me a 2 minute warning."),
            ("seat a four year old", "Seat a 4 year old."),
            ("i two think so", "I two think so."),
            ("we need a three", "We need a 3."),
            ("is this a four day trip", "Is this a 4 day trip?"),
            ("tell her a three word answer", "Tell her a 3 word answer."),
            ("s nine is not a bucket", "S 9 is not a bucket."),
        ])
    func keeps(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }
}
