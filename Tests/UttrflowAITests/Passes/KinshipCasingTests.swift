import Testing
@testable import UttrflowCore

@testable import UttrflowAI

@Suite("Kinship words used as a name")
struct KinshipCasingTests {
    private let sut = FirstWordPass()

    @Test(
        "a kinship word with no article or possessive just before it is a name",
        arguments: [
            ("tell mom i am late", "Tell Mom I am late"),
            ("ask dad about the car", "Ask Dad about the car"),
            ("i called mummy yesterday", "I called Mummy yesterday"),
            ("kal papa ko bol dena", "Kal Papa ko bol dena"),
            ("abhi didi aa rahi hai", "Abhi Didi aa rahi hai"),
            ("okay mom said yes", "Okay Mom said yes"),
            ("we met grandma at noon", "We met Grandma at noon"),
            ("thanks, dad", "Thanks, Dad"),
            ("kya bhaiya ghar par hai", "Kya Bhaiya ghar par hai"),
            ("send it to papa tonight", "Send it to Papa tonight"),
            ("then mum laughed", "Then Mum laughed"),
            ("is dad's phone charged", "Is Dad's phone charged"),
            ("love you mommy", "Love you Mommy"),
            ("subah nani ka phone aaya", "Subah Nani ka phone aaya"),
            ("call grandpa after lunch", "Call Grandpa after lunch"),
            ("kal chacha aa rahe hain", "Kal Chacha aa rahe hain"),
            ("i told daddy already", "I told Daddy already"),
            ("ab bhabhi ko batao", "Ab Bhabhi ko batao"),
            ("did Mom reply", "Did Mom reply"),
            ("so mausi said no", "So Mausi said no"),
        ])
    func capitalisesTheName(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "an article or possessive up to one word before a kinship word keeps it a common noun",
        arguments: [
            ("i told my mom", "I told my mom"),
            ("her dad is a pilot", "Her dad is a pilot"),
            ("she is a great mom", "She is a great mom"),
            ("the dad in the film", "The dad in the film"),
            ("mere papa ghar par hai", "Mere papa ghar par hai"),
            ("ask your mum first", "Ask your mum first"),
            ("their grandma cooks", "Their grandma cooks"),
            ("meri didi aa rahi hai", "Meri didi aa rahi hai"),
            ("his daddy works late", "His daddy works late"),
            ("our grandpa is ninety", "Our grandpa is ninety"),
            ("apne bhaiya ko bolo", "Apne bhaiya ko bolo"),
            ("uski mummy ne bola", "Uski mummy ne bola"),
            ("i told my Mom", "I told my mom"),
            ("this dad joke again", "This dad joke again"),
            ("a proud mom", "A proud mom"),
            ("tumhare chacha kab aayenge", "Tumhare chacha kab aayenge"),
            ("an old mum", "An old mum"),
            ("hamari nani ka ghar", "Hamari nani ka ghar"),
            ("my dad's car", "My dad's car"),
            ("that new mom", "That new mom"),
        ])
    func keepsTheCommonNoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("the kinship table loads from the bundle and every row is Latin lower case")
    func bundledAndLatin() {
        #expect(KinshipWords.table.source == .bundled)
        for row in KinshipWords.table.rows {
            #expect(row.id.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isLowercase }, "\(row.id)")
            #expect(!row.languages.isEmpty, "\(row.id)")
        }
    }
}
