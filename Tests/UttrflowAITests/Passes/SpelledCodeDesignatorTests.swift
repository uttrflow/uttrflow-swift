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
            ("use paper size a four", "Use paper size a four."),
            ("room twelve b, then left", "Room 12B, then left."),
            ("gate b twelve.", "Gate B12."),
            ("go to row twelve c", "Go to row 12C."),
            ("the code is b one", "The code is b one."),
        ])
    func joins(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves the article, a pronoun and a letter with no evidence as spoken",
        arguments: [
            ("a three bedroom flat", "A three bedroom flat."),
            ("a four week plan", "A four week plan."),
            ("a four hour delay", "A four hour delay."),
            ("we need plan b", "We need plan b."),
            ("take vitamin c", "Take vitamin c."),
            ("i have two", "I have two."),
            ("q five is not a quarter", "Q five is not a quarter."),
            ("p nine is not a priority", "P nine is not a priority."),
            ("give me a two minute warning", "Give me a two minute warning."),
            ("seat a four year old", "Seat a four year old."),
            ("i two think so", "I two think so."),
        ])
    func keeps(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }
}
