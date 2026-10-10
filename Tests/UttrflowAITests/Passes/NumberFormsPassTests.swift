import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass")
struct NumberFormsPassTests {
    private let sut = NumberFormsPass()

    @Test(
        "writes a numeric date said with slash, stroke or dash in the spoken order, padded as spoken",
        arguments: [
            ("oh three slash oh four slash twenty twenty five", "03/04/2025"),
            ("on twelve slash twenty five slash twenty four we met", "on 12/25/24 we met"),
            ("twenty five slash twelve slash twenty twenty four", "25/12/2024"),
            ("three dash four dash oh five", "3-4-05"),
            ("five stroke nine stroke nineteen ninety nine", "5/9/1999"),
            ("read and slash or write", "read and slash or write"),
            ("three slash four", "three slash four"),
            ("three slash four dash twenty twenty five", "three slash four dash 2025"),
            ("twenty five slash twenty six slash twenty twenty", "25 slash 26 slash 2020"),
        ]
    )
    func numericDates(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes every number of a coordinated group as a numeral once one of them is",
        arguments: [
            ("between five and fifteen", "between 5 and 15"),
            ("three or twelve", "3 or 12"),
            ("one, five and twenty", "1, 5 and 20"),
            ("five, ten, and fifteen minutes", "5, 10, and 15 minutes"),
            ("from five to fifteen people", "from 5 to 15 people"),
            ("nine through eleven", "9 through 11"),
            ("eight versus twelve", "8 versus 12"),
            ("two or 30", "2 or 30"),
            ("between 4 and nine", "between 4 and 9"),
            ("one of the 12 people", "one of the 12 people"),
            ("three apples and twelve pears", "three apples and 12 pears"),
            ("one or two", "one or two"),
            ("five, six and seven", "five, six and seven"),
            ("one, five. Then twenty", "one, five. Then 20"),
            ("ten to six", "10 to six"),
        ]
    )
    func coordinatedGroups(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .fromTen)) == expected)
    }

    @Test(
        "writes a number from ten up as a numeral, with commas only from ten thousand",
        arguments: [
            ("about fifteen people", "about 15 people"),
            ("twenty one days", "21 days"),
            ("one hundred and five", "105"),
            ("nine thousand rupees", "9000 rupees"),
            ("fifteen thousand users", "15,000 users"),
            ("two million", "2,000,000"),
            ("two billion dollars", "2,000,000,000 dollars"),
            ("two trillion dollars", "2,000,000,000,000 dollars"),
            ("two million dollars", "2,000,000 dollars"),
            ("nineteen hundred", "1900"),
            ("two thousand and five", "2005"),
            ("the nineteen nineties were fun", "the 1990s were fun"),
            ("it's a twenty four seven service", "it's a twenty four seven service"),
            ("it's fifty fifty", "it's fifty fifty"),
            ("fifteen,", "15,"),
            ("\"twenty\"", "\"20\""),
            ("twenty, one", "20, one"),
            ("five dollars", "5 dollars"),
            ("fifteen thousand dollars", "15,000 dollars"),
            ("it's negative fifteen degrees outside", "it's -15 degrees outside"),
            ("the account is minus two hundred dollars", "the account is -200 dollars"),
            ("minus fifteen point two", "-15.2"),
            ("negative 5", "-5"),
            ("minus five dollars", "-5 dollars"),
            ("port negative five", "port -5"),
            ("negative five degrees", "negative five degrees"),
            ("negative, fifteen degrees", "negative, 15 degrees"),
            ("it was minus fifteen outside", "it was -15 outside"),
            ("the balance is five hundred minus fifty", "the balance is 500 minus 50"),
            ("twenty minus twelve", "20 - 12"),
            ("15 minus 3", "15 - 3"),
            ("five, dollars", "five, dollars"),
            ("a dollar", "a dollar"),
        ]
    )
    func wholeNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes operators and numerals only where a whole sentence is arithmetic",
        arguments: [
            ("five plus three equals eight", "5 + 3 = 8"),
            ("Five plus three equals eight.", "5 + 3 = 8."),
            ("two times four is eight", "two times four is eight"),
            ("six times seven equals forty two", "6 × 7 = 42"),
            ("twelve divided by four equals three", "12 ÷ 4 = 3"),
            ("nine greater than two", "9 > 2"),
            ("one less than two", "1 < 2"),
            ("ten multiplied by ten", "10 × 10"),
            ("We counted. Five plus five equals ten.", "We counted. 5 + 5 = 10."),
            ("plus we need milk", "plus we need milk"),
            ("five plus we need milk", "five plus we need milk"),
            ("everything minus the tax", "everything minus the tax"),
            ("three times a day", "three times a day"),
            ("it equals the sum", "it equals the sum"),
            ("five plus", "five plus"),
            ("plus five", "plus five"),
            ("five plus plus three", "five plus plus three"),
            ("the total is five plus three", "the total is five plus three"),
        ]
    )
    func arithmeticSentences(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes an operator between numbers anywhere when every number is a numeral",
        arguments: [
            ("the total is five plus three", "the total is 5 + 3"),
            ("three times a day", "3 times a day"),
            ("plus we need milk", "plus we need milk"),
        ]
    )
    func arithmeticWhereNumeralsAlways(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test(
        "writes every part of a spoken amount in one form",
        arguments: [
            ("three dollars and five cents", "3 dollars and 5 cents"),
            ("nine dollars and nine cents", "9 dollars and 9 cents"),
            ("it costs five euros and five cents", "it costs 5 euros and 5 cents"),
            ("two dollars fifty", "2 dollars 50"),
            ("five pounds and fifty pence", "5 pounds and 50 pence"),
            ("twelve dollars and fifty cents", "12 dollars and 50 cents"),
            ("a dollar and five cents", "a dollar and five cents"),
            ("five dollars. five cents", "5 dollars. five cents"),
            ("it is my two cents", "it is my two cents"),
        ]
    )
    func amounts(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "joins spoken percentile ranks",
        arguments: [
            ("p fifty", "p50"), ("p ninety", "p90"), ("p ninety five", "p95"),
            ("p ninety nine", "p99"), ("p ninety nine point nine", "p99.9"),
        ]
    )
    func percentiles(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
        #expect(cleaned("plan p two", by: sut) == "plan p two")
    }

    /// A cell, a query and a line of code want the numeral; prose wants the word. See the design's §2 table.
    @Test(
        "writes every number as a numeral where the place asks for all of them",
        arguments: [
            ("one of them", "1 of them"),
            ("zero", "0"),
            ("two to three", "2 to 3"),
            ("about fifteen people", "about 15 people"),
            ("nine thousand rupees", "9000 rupees"),
        ]
    )
    func everyNumberAsANumeral(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test(
        "reads a hyphenated tens-unit number as one number",
        arguments: [
            ("twenty-one dollars", "21 dollars"),
            ("ninety-nine percent", "99%"),
            ("forty-two", "42"),
            ("Forty-two, then", "42, then"),
            ("three hundred forty-five people", "345 people"),
            ("forty-five thousand", "45,000"),
        ]
    )
    func hyphenatedTensUnit(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test("reads a hyphenated tens-unit number from ten up, and keeps a hyphen that is not one")
    func hyphenatedTensUnitFromTen() {
        #expect(cleaned("twenty-one", by: sut) == "21")
        #expect(cleaned("at twenty-one", by: sut) == "at 21")
        #expect(cleaned("a well-known one-off", by: sut) == "a well-known one-off")
    }

    @Test(
        "a pronoun one stays a word where every number is a numeral",
        arguments: [
            ("no one knows", "no one knows"),
            ("they help one another", "they help one another"),
            ("which one is it", "which one is it"),
            ("this one works", "this one works"),
            ("the one that matters", "the one that matters"),
            ("one by one they left", "one by one they left"),
            ("any one of us", "any one of us"),
            ("take each one", "take each one"),
            ("I want that one", "I want that one"),
            ("we need one reviewer", "we need 1 reviewer"),
            ("add one row", "add 1 row"),
            ("the one reviewer", "the 1 reviewer"),
        ]
    )
    func pronounOneStaysAWord(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test(
        "a small amount in another currency or unit is a numeral in prose",
        arguments: [
            ("it costs five yen", "it costs 5 yen"),
            ("we walked three kilometres", "we walked 3 kilometres"),
            ("wait two minutes", "wait 2 minutes"),
            ("one of them", "one of them"),
            ("I lost a pound", "I lost a pound"),
            ("I lost one pound", "I lost 1 pound"),
            ("give me a second", "give me a second"),
            ("two seconds", "two seconds"),
            ("six feet", "six feet"),
        ]
    )
    func smallAmountsAreNumerals(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .fromTen)) == expected)
    }

    @Test(
        "a small number before a unit symbol, written or spelled, is a numeral in prose",
        arguments: [
            ("with eight g b of ram", "with 8 g b of ram"),
            ("I have eight GB of RAM", "I have 8 GB of RAM"),
            ("take five m g twice a day", "take 5 m g twice a day"),
            ("a two t b drive", "a 2 t b drive"),
            ("an eight k b page", "an 8 k b page"),
            ("eight g b a", "eight g b a"),
            ("two p s", "two p s"),
            ("one of them", "one of them"),
        ]
    )
    func smallAmountsBeforeAUnitSymbolAreNumerals(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .fromTen)) == expected)
    }

    @Test("the place a dictation lands in decides how many of its numbers are numerals")
    func policyComesFromTheFormatter() {
        #expect(cleaned("one of them", by: NumberFormsPass(policy: .fromTen)) == "one of them")
        #expect(cleaned("one of them", by: NumberFormsPass()) == "one of them")
        #expect(NumberFormsPass(policy: .always).policy == .always)
    }

    /// Writing only the tail of a phrase the parser could not read whole says a number the speaker did not.
    @Test(
        "leaves a scale phrase whole rather than writing the part after its and",
        arguments: [
            "about a hundred and fifty users", "a thousand and twenty of them",
            "roughly a hundred and fifteen",
        ]
    )
    func leavesAnUnparsedScaleWhole(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A number reads its context from its own sentence, so neither a labelling word nor a scale binds across a stop.
    @Test(
        "reads no context word and no scale tail from the sentence before",
        arguments: [
            ("we are in the room. Six people came", "we are in the room. Six people came"),
            ("turn to the page. Four of them left", "turn to the page. Four of them left"),
            ("check the version. Three times today", "check the version. Three times today"),
            ("I have a hundred. And fifty people came", "I have a hundred. And 50 people came"),
            ("we counted a thousand. And twenty came", "we counted a thousand. And 20 came"),
        ]
    )
    func readsNoContextAcrossASentenceEnd(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps a single digit as a word unless something makes it a number",
        arguments: [
            "one of them", "the one", "two to three", "zero", "a hundred", "hundred", "point five",
            "15 people",
        ]
    )
    func keepsWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "writes digits after a labelling word, run together and never grouped",
        arguments: [
            ("port eight thousand eighty", "port 8080"),
            ("port eighty eighty", "port 8080"),
            ("port fifty thousand", "port 50000"),
            ("version two point four point one", "version 2.4.1"),
            ("page two", "page 2"),
            ("page two of three", "page 2 of 3"),
            ("step three", "step 3"),
            ("chapter one", "chapter 1"),
            ("extension four five six", "extension 456"),
            ("number one priority", "number 1 priority"),
            ("port 8080", "port 8080"),
        ]
    )
    func labelledNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("ordinary cardinal conversion stays intact beside protected expressions")
    func ordinaryNumbersRemainUnchanged() {
        #expect(cleaned("twenty four people and fifty users", by: sut) == "24 people and 50 users")
    }

    @Test(
        "writes three or more spoken single digits as one digit string",
        arguments: [
            ("call me on nine eight seven six five four three two one zero", "call me on 9876543210"),
            ("the code is one two three four", "the code is 1234"),
            ("call nine one one", "call 911"),
            ("dial plus nine one nine eight seven six five four three two one zero", "dial +919876543210"),
            ("the passcode is zero oh five", "the passcode is 005"),
            ("the passcode is oh five zero", "the passcode is 050"),
        ]
    )
    func writesSpokenDigitRuns(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes an offset from UTC or GMT as the zone, a sign, the hour and any half hour",
        arguments: [
            ("u t c plus five thirty", "UTC+5:30"),
            ("utc plus five thirty", "UTC+5:30"),
            ("g m t minus eight", "GMT-8"),
            ("gmt plus eight", "GMT+8"),
            ("UTC plus 5", "UTC+5"),
            ("u t c plus five forty five", "UTC+5:45"),
            ("plus five points", "plus five points"),
        ]
    )
    func writesZoneOffsets(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "reads double, triple and quadruple before a digit word inside a digit run",
        arguments: [
            ("double oh seven", "007"),
            ("triple five one two", "55512"),
            ("call five five double two", "call 5522"),
            ("the room is quadruple one", "the room is 1111"),
            ("double check the list", "double check the list"),
            ("double two", "double two"),
            ("a double espresso and one two", "a double espresso and one two"),
        ]
    )
    func readsRepeatedDigits(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps two single digits and number words in a hyphenated count",
        arguments: [
            "one or two",
            "two three-bedroom flats",
        ]
    )
    func keepsDigitAndCountContrasts(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps a count-off or countdown with no introducing word as words",
        arguments: [
            "three two one go",
            "one two three testing",
            "five four three two one liftoff",
            "ready? three two one",
            "four three two one and we are live",
            "two three four five six seven",
            "seven six five four",
            "one two three four five, you know the rest",
            "six seven eight nine and go",
            "nine eight seven six five four three two one",
            "she counted one two three out loud",
            "and one two three four",
        ]
    )
    func keepsUncuedCountsAsWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "joins a count after a word that introduces a number",
        arguments: [
            ("my pin is one two three four", "my pin is 1234"),
            ("the code is four three two one", "the code is 4321"),
            ("dial one two three", "dial 123"),
            ("extension two three four", "extension 234"),
            ("room three four five", "room 345"),
            ("call nine one one", "call 911"),
            ("the otp is five six seven eight", "the otp is 5678"),
            ("flight one two three", "flight 123"),
            ("call me on nine eight seven six", "call me on 9876"),
            ("page three two one", "page 321"),
            ("password one two three", "password 123"),
            ("my number was three four five six", "my number was 3456"),
        ]
    )
    func joinsCuedCounts(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("writes a count as separate numerals where every number is a numeral")
    func countInSpreadsheetCell() {
        #expect(cleaned("three two one", by: NumberFormsPass(policy: .always, digits: .none)) == "3 2 1")
    }

    @Test(
        "keeps a run of only zero words as words",
        arguments: ["oh oh oh that is great", "zero zero zero", "oh oh no"]
    )
    func keepsAllZeroRuns(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("does not join single digits that a scale word follows")
    func keepsDigitsBeforeAScale() {
        #expect(!cleaned("it was one one one hundred", by: sut).contains("111 hundred"))
    }

    @Test("keeps a digit string after an intervening is")
    func keepsExtensionDigitsAfterIs() {
        #expect(cleaned("my extension is 445", by: sut) == "my extension is 445")
    }

    @Test(
        "writes decimals, percentages and versions",
        arguments: [
            ("sixteen point two", "16.2"),
            ("two point five", "2.5"),
            ("three point one four", "3.14"),
            ("sixteen point twenty five", "16.25"),
            ("five percent", "5%"),
            ("twenty five per cent", "25%"),
            ("2.5 percent", "2.5%"),
            ("five percent.", "5%."),
            ("two point five percent", "2.5%"),
            ("one point is that", "one point is that"),
            ("sixteen point 2", "16.2"),
            ("point five percent", "0.5%"),
            ("point five per cent", "0.5%"),
            ("minus point two", "-0.2"),
            ("negative point two five", "-0.25"),
            ("a point five second delay", "a 0.5 second delay"),
            ("point five kilometres", "0.5 kilometres"),
            ("this point five of us", "this point five of us"),
            ("a good point five minutes ago", "a good point 5 minutes ago"),
        ]
    )
    func decimals(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes a spoken dot between digit groups as a dot when three groups or a cue say so",
        arguments: [
            ("one nine two dot one six eight dot one dot one", "192.168.1.1"),
            ("the ip is ten dot zero dot zero dot one", "the ip is 10.0.0.1"),
            ("install two dot one dot three", "install 2.1.3"),
            ("version two dot five", "version 2.5"),
            ("build twelve dot four", "build 12.4"),
            ("two dot five", "two dot five"),
            ("dot five", "dot five"),
            ("the dot com bubble", "the dot com bubble"),
            ("one dot product", "one dot product"),
            ("ten dot com", "10 dot com"),
        ]
    )
    func dottedNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes times of day",
        arguments: [
            ("two thirty pm", "2:30 pm"),
            ("meet at two thirty", "meet at 2:30"),
            ("I have two twenty dollar bills", "I have two 20 dollar bills"),
            ("take three fifteen minute breaks", "take three 15 minute breaks"),
            ("we got a four oh four error", "we got a 404 error"),
            ("ten am", "10 am"),
            ("ten a.m.", "10 a.m."),
            ("two oh five pm", "2:05 pm"),
            ("at eight oh five", "at 8:05"),
            ("at eight oh five am", "at 8:05 am"),
            ("eight oh five am", "8:05 am"),
            ("at twelve o five", "at 12:05"),
            ("call at eight oh five five five", "call at 80555"),
            ("the code eight oh five", "the code 805"),
            ("five o'clock", "5 o'clock"),
            ("at four thirty", "at 4:30"),
            ("by two thirty", "by 2:30"),
            ("until two thirty", "until 2:30"),
            ("from two thirty", "from 2:30"),
            ("twelve fifteen pm", "12:15 pm"),
            ("2 thirty pm", "2:30 pm"),
            ("one thirty", "1:30"),
            ("five thirty.", "5:30."),
            ("let us meet around five thirty", "let us meet around 5:30"),
            ("five forty five", "5:45"),
            ("leave before six fifteen", "leave before 6:15"),
            ("after two thirty we eat", "after 2:30 we eat"),
            ("two forty five pm", "2:45 pm"),
        ]
    )
    func times(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A relative clock phrase keeps every word; only the place's number policy reaches the numbers in it.
    @Test(
        "keeps the words of a relative clock phrase under either policy",
        arguments: [
            ("meet at half past two", "meet at half past two", "meet at half past 2"),
            ("leave at quarter to six", "leave at quarter to six", "leave at quarter to 6"),
            ("it is twenty past four", "it is 20 past four", "it is 20 past 4"),
            ("ten to six", "10 to six", "10 to 6"),
            ("a quarter past eleven", "a quarter past 11", "a quarter past 11"),
        ]
    )
    func relativeClockPhrases(input: String, fromTen: String, always: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .fromTen)) == fromTen)
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == always)
    }

    @Test(
        "writes a 24-hour time only with a cue",
        arguments: [
            ("the train leaves at thirteen oh five", "the train leaves at 13:05"),
            ("meet at fourteen thirty", "meet at 14:30"),
            ("open until twenty three fifty nine", "open until 23:59"),
            ("report at oh nine thirty", "report at 09:30"),
            ("we move at oh nine hundred hours", "we move at 0900 hours"),
            ("briefing is at eighteen hundred hours", "briefing is at 1800 hours"),
            ("fourteen thirty hours", "1430 hours"),
            ("fourteen thirty people came", "14 30 people came"),
            ("twenty one thirty", "21 30"),
            ("nineteen hundred", "1900"),
            ("we live at twelve hundred fourth avenue", "we live at 1200 fourth avenue"),
        ]
    )
    func twentyFourHourTimes(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes compound ordinals outside dates",
        arguments: [
            ("it is the forty second floor", "it is the 42nd floor"),
            ("he came twenty first in the race", "he came 21st in the race"),
            ("the thirty first floor", "the 31st floor"),
            ("on the fifty fifth day", "on the 55th day"),
            ("the twenty fifth anniversary", "the 25th anniversary"),
            ("we finished twenty third", "we finished 23rd"),
            ("the one hundred and twenty first floor", "the 121st floor"),
            ("the one hundred and first visitor", "the 101st visitor"),
            ("the one hundred and first", "the 101st"),
            ("the one hundred and twentieth day", "the 120th day"),
            ("the one hundred twenty first floor", "the 121st floor"),
            ("the one thousand and first night", "the 1001st night"),
            ("the one hundred and twenty-first floor", "the 121st floor"),
            ("the two hundred and fiftieth year", "the 250th year"),
            ("the one hundred and twelfth day", "the 112th day"),
            ("the 121st floor", "the 121st floor"),
            ("the twenty-fifth floor", "the 25th floor"),
        ]
    )
    func compoundOrdinals(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "joins a colloquial hundred when it cannot be a time",
        arguments: [
            ("blood pressure one twenty seven over eighty two", "blood pressure 127 over 82"),
            ("bp is one fifty over ninety five", "bp is 150 over 95"),
            ("ldl one sixty five", "ldl 165"),
            ("he weighs one ninety", "he weighs 190"),
            ("route one twenty eight", "route 128"),
            ("flight one twenty three", "flight 123"),
            ("interstate four fifty", "interstate 450"),
            ("meet in room two twelve", "meet in room 212"),
            ("one oh five over sixty", "105 over 60"),
            ("one twenty over there", "one twenty over there"),
            ("I have two twenty dollar bills", "I have two 20 dollar bills"),
        ]
    )
    func colloquialHundreds(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps both words of a pair that may be a time or one number, unless the second counts a noun",
        arguments: [
            ("return four thirteen when it fails", "return four thirteen when it fails"),
            ("call me five thirty then", "call me five thirty then"),
            ("we have four thirteen year olds", "we have four 13 year olds"),
            ("take three fifteen minute breaks", "take three 15 minute breaks"),
            ("at four thirteen we left", "at 4:13 we left"),
            ("room four thirteen is free", "room 413 is free"),
        ]
    )
    func undecidedPairsKeepTheirWords(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps a house number apart from an ordinal street name",
        arguments: [
            ("nine hundred fifth avenue", "900 fifth avenue"),
            ("the shop is at nine hundred fifth avenue", "the shop is at 900 fifth avenue"),
            ("he lives at four hundred second street", "he lives at 400 second street"),
            ("we live at twelve hundred fourth avenue", "we live at 1200 fourth avenue"),
            ("two thousand third road", "2000 third road"),
            ("forty two oak street", "42 oak street"),
            ("the store is on fifth avenue", "the store is on fifth avenue"),
            ("the nine hundred fifth visitor", "the 905th visitor"),
        ]
    )
    func houseNumberBeforeOrdinalStreet(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("normalizes dotted times only with a clock cue")
    func dottedTimes() {
        #expect(cleaned("moved to 4.30 p.m. on June 2", by: sut) == "moved to 4:30 p.m. on June 2")
        #expect(cleaned("lands at 7.15, so book a cab", by: sut) == "lands at 7:15, so book a cab")
        #expect(cleaned("version 2.4.1", by: sut) == "version 2.4.1")
        #expect(cleaned("12.5% and $3.50", by: sut) == "12.5% and $3.50")
        #expect(cleaned("the ratio is 7.15", by: sut) == "the ratio is 7.15")
        #expect(cleaned("lands at 14.30 today", by: sut) == "lands at 14:30 today")
        #expect(cleaned("14.30 pm", by: sut) == "14.30 pm")
    }

    /// Every time cue reads a dotted clock; a unit, a percent or another digit group after it says it is a quantity.
    @Test(
        "reads a dotted number as a clock after any time cue but never before a unit",
        arguments: [
            ("open until 9.45 tonight", "open until 9:45 tonight"),
            ("stay till 9.45 tonight", "stay till 9:45 tonight"),
            ("call around 9.45 tomorrow", "call around 9:45 tomorrow"),
            ("leave before 9.45 or we miss it", "leave before 9:45 or we miss it"),
            ("free after 9.45 today", "free after 9:45 today"),
            ("we run from 9.45 to noon", "we run from 9:45 to noon"),
            ("the alarm for 6.30 is set", "the alarm for 6:30 is set"),
            ("tickets sell at 3.50 dollars each", "tickets sell at 3.50 dollars each"),
            ("rates sit at 3.50 percent now", "rates sit at 3.50% now"),
            ("rates sit at 3.50 per cent now", "rates sit at 3.50% now"),
            ("rates sit at 3.50% now", "rates sit at 3.50% now"),
            ("held at 3.5 percent", "held at 3.5%"),
            ("the bag weighs about 2.30 kilograms", "the bag weighs about 2.30 kilograms"),
            ("it finished in under 9.45 seconds", "it finished in under 9.45 seconds"),
            ("set the rows at 3.30 45 and 60", "set the rows at 3.30 45 and 60"),
        ]
    )
    func dottedTimeCuesAndQuantities(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A run of three or more single digits is a digit string, never a clock time; a clock time needs a cue or a non-digit-run minute.
    @Test(
        "writes single-digit runs as a digit string",
        arguments: [
            ("the pin is five zero one two", "the pin is 5012"),
            ("my extension is three zero two", "my extension is 302"),
            ("the code is six zero five nine", "the code is 6059"),
            ("dial one eight hundred five five five zero one nine nine", "dial one 800 5550199"),
            ("two hundred five five", "200 five five"),
            ("two thousand three four five", "2000 345"),
            ("we have two hundred five users", "we have 205 users"),
            ("twenty five five five", "25 five five"),
            ("one hundred twenty three four five six", "123 456"),
        ]
    )
    func digitRuns(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("preserves every toll-free spoken digit in order")
    func tollFreeDigitOrder() {
        let output = cleaned("dial one eight hundred five five five zero one nine nine", by: sut)
        #expect(output == "dial one 800 5550199")
        #expect(output.filter(\.isNumber) == "8005550199")
    }

    @Test("keeps the unit in a cardinal before a currency")
    func scaleCardinalBeforeCurrency() {
        #expect(cleaned("eight hundred five dollars", by: sut) == "805 dollars")
    }

    /// A digit run still becomes a clock time when a cue ("at", am/pm, o'clock) sits before or after the run.
    @Test(
        "keeps a clock time when the digit run has a time cue",
        arguments: [
            ("at five zero one", "at 5:01"),
            ("two zero one pm", "2:01 pm"),
            ("five zero one two am", "5012 am"),
        ]
    )
    func digitRunsWithTimeCue(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "reads for as a time cue only after a noun that takes a time",
        arguments: [
            ("set the alarm for seven thirty tomorrow", "set the alarm for 7:30 tomorrow"),
            ("a reminder for six fifteen today", "a reminder for 6:15 today"),
            ("we waited for seven thirty minutes", "we waited for seven 30 minutes"),
            ("the alarm. for seven thirty days", "the alarm. for seven 30 days"),
        ]
    )
    func forAfterTimedNoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes years spoken in two halves",
        arguments: [
            ("twenty twenty four", "2024"),
            ("nineteen ninety nine", "1999"),
            ("twenty ten", "2010"),
            ("in twenty twenty", "in 2020"),
            ("in twenty oh five", "in 2005"),
            ("since nineteen oh one", "since 1901"),
            ("from nineteen oh five until twenty oh nine", "from 1905 until 2009"),
            ("in two thousand", "in 2000"),
            ("in two thousand five", "in 2005"),
            ("in two thousand and five", "in 2005"),
            ("March twenty oh five", "March 2005"),
            ("twenty oh five people", "20 oh five people"),
        ]
    )
    func years(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes dates from ordinals before months",
        arguments: [
            ("third of June", "third of June"),
            ("the third of June", "the third of June"),
            ("twenty fifth of March", "25th of March"),
            ("the twenty first of march", "the 21st of March"),
            ("twenty first of march", "21st of March"),
            ("eleventh of May", "11th of May"),
            ("twelfth of May", "12th of May"),
            ("thirteenth of May", "13th of May"),
            ("first of January", "first of January"),
            ("thirty first of December", "31st of December"),
            ("twenty fifth March", "25th March"),
            ("tenth of April", "10th of April"),
        ]
    )
    func dates(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes dates from ordinals before months under always policy",
        arguments: [
            ("third of June", "3rd of June"),
            ("the third of June", "the 3rd of June"),
            ("first of January", "1st of January"),
        ]
    )
    func datesAlwaysPolicy(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test(
        "writes dates with the month before the ordinal",
        arguments: [
            ("March third", "March 3"),
            ("the third of March", "the 3rd of March"),
            ("let's meet May fifth", "let's meet May 5"),
            ("March third twenty twenty five", "March 3, 2025"),
        ]
    )
    func datesWithMonthBeforeOrdinal(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test(
        "writes a spoken year as part of its date, in the spoken order",
        arguments: [
            ("March twenty fifth twenty twenty six", "March 25, 2026"),
            ("March twenty fifth", "March 25"),
            ("on March twenty fifth twenty twenty six we met", "on March 25, 2026 we met"),
            ("December thirty first nineteen ninety nine", "December 31, 1999"),
            ("March twenty fifth 2026", "March 25, 2026"),
            ("March twenty fifth, twenty twenty six", "March 25, 2026"),
            ("twenty fifth of March twenty twenty six", "25th of March 2026"),
            ("the twenty fifth of March twenty twenty six", "the 25th of March 2026"),
            ("twenty fifth March twenty twenty six", "25th March 2026"),
            ("twenty fifth of March", "25th of March"),
            ("tenth of April nineteen ninety nine", "10th of April 1999"),
            ("twenty fifth of March 2026", "25th of March 2026"),
        ]
    )
    func datesWithYears(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves dates the recogniser already wrote unchanged",
        arguments: ["March 25, 2026", "25 March 2026", "March 25 2026", "25th of March, 2026", "3/25/2026"]
    )
    func writtenDatesUnchanged(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("a date with its year keeps every quantity the meaning guard counts")
    func datesKeepQuantities() {
        let original = "March twenty fifth twenty twenty six"
        let written = cleaned(original, by: sut)
        #expect(MeaningPreservationGuard.changedQuantity(original: original, rewritten: written) == nil)
    }

    @Test("month-first dates keep the number policy and reject ambiguous or impossible dates")
    func monthFirstDatesRespectPolicyAndValidity() {
        #expect(cleaned("March third", by: sut) == "March third")
        #expect(cleaned("third of March", by: sut) == "third of March")
        #expect(cleaned("March twenty fifth", by: sut) == "March 25")
        #expect(cleaned("march third", by: NumberFormsPass(policy: .always)) == "March 3")
        #expect(cleaned("it is may twelfth", by: sut) == "it is May 12")
        #expect(cleaned("you may go", by: NumberFormsPass(policy: .always)) == "you may go")
        #expect(cleaned("we may first", by: NumberFormsPass(policy: .always)) == "we may first")
        #expect(cleaned("March thirty second", by: NumberFormsPass(policy: .always)) == "March thirty second")
    }

    @Test(
        "recognises hyphenated dates and preserves their surrounding punctuation",
        arguments: [
            ("twenty-fifth of March", "25th of March"),
            ("TWENTY FIRST OF MAY", "21st of May"),
            ("twentieth june", "20th June"),
            ("thirtieth September", "30th September"),
            ("twenty ninth of February", "29th of February"),
            ("twenty fifth May", "25th May"),
            ("\"twenty fifth of March.\"", "\"25th of March.\""),
            ("twenty-fifth June, twenty sixth July", "25th June, 26th July"),
        ]
    )
    func dateForms(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps ambiguous, impossible and interrupted ordinals intact under both policies",
        arguments: [
            "the first may fail", "the tenth may fail", "the twenty first may fail",
            "the second march was peaceful", "the twentieth march was peaceful",
            "thirty second of January", "ninety ninth of May", "thirty first of April",
            "thirtieth February", "twenty fifth of Smarch", "twenty fifth of",
            "twenty fifth, March", "tenth of, April", "tenth of \"April\"",
            "twenty--fifth of March",
            "twenty-tenth of March", "first", "a hundred and twentieth of June",
        ]
    )
    func preservesOrdinals(input: String) {
        for policy in [NumberPolicy.fromTen, .always] {
            #expect(cleaned(input, by: NumberFormsPass(policy: policy)) == input)
        }
    }

    @Test("an ambiguous ordinal stays untouched in the edit history")
    func untouchedOrdinalProvenance() {
        let draft = Draft(text: "the twenty first may fail")
        #expect(sut.apply(draft) == draft)
    }

    @Test("a date records only its replaced ordinal and removed words")
    func dateProvenance() {
        let draft = sut.apply(Draft(text: "twenty fifth of March"))
        #expect(draft.words[0].state == .replaced(by: NumberFormsPass.id, from: "twenty"))
        #expect(draft.words[1].state == .removed(by: NumberFormsPass.id))
        #expect(draft.words[2].state == .removed(by: NumberFormsPass.id))
    }

    @Test("leaves numbers in other languages alone")
    func otherLanguages() {
        #expect(cleaned("बीस मिनट", by: sut) == "बीस मिनट")
    }

    @Test("records the numeral as a replacement and the other words as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "twenty one days"))
        #expect(draft.words[0].state == .replaced(by: NumberFormsPass.id, from: "twenty"))
        #expect(draft.words[1].state == .removed(by: NumberFormsPass.id))
        #expect(draft.words[2].state == .kept)
    }
}

@Suite("NumberWords")
struct NumberWordsTests {
    private func cardinal(_ words: String) -> (Int, Int)? {
        NumberWords.cardinal(words.split(separator: " ").map(String.init)[...]).map { ($0.value, $0.count) }
    }

    @Test(
        "reads the longest cardinal at the start and says how many words it used",
        arguments: [
            ("fifteen", 15, 1),
            ("twenty one", 21, 2),
            ("twenty twenty", 20, 1),
            ("two hundred", 200, 2),
            ("one hundred and five", 105, 4),
            ("two thousand and", 2000, 2),
            ("eight thousand eighty", 8080, 3),
            ("zero", 0, 1),
            ("five zero", 5, 1),
            ("one million two hundred thousand", 1_200_000, 5),
            ("two billion", 2_000_000_000, 2),
            ("twelve billion", 12_000_000_000, 2),
            ("twelve trillion", 12_000_000_000_000, 2),
            ("twenty and five", 20, 1),
            ("three hundred hundred", 300, 2),
            ("nine thousand thousand", 9000, 2),
        ]
    )
    func cardinals(words: String, value: Int, count: Int) {
        #expect(cardinal(words).map { $0.0 } == value)
        #expect(cardinal(words).map { $0.1 } == count)
    }

    @Test("reads nothing from words that are not a number", arguments: ["hundred", "and five", "hello", ""])
    func notNumbers(words: String) {
        #expect(cardinal(words) == nil)
    }

    @Test("knows a numeral already in digits")
    func digits() {
        #expect(NumberWords.digits("15") == "15")
        #expect(NumberWords.digits("16.2") == "16.2")
        #expect(NumberWords.digits("2:30") == "2:30")
        #expect(NumberWords.digits("15.") == nil)
        #expect(NumberWords.digits("1st") == nil)
        #expect(
            NumberWords.isNumber("15") && NumberWords.isNumber("fifteen") && !NumberWords.isNumber("hello"))
    }

    @Test("groups thousands with commas only from ten thousand")
    func grouping() {
        #expect(NumberWords.render(9999, grouping: .thousands) == "9999")
        #expect(NumberWords.render(10_000, grouping: .thousands) == "10,000")
        #expect(NumberWords.render(1_234_567, grouping: .thousands) == "1,234,567")
        #expect(NumberWords.render(1_234_567, grouping: .none) == "1234567")
    }

    @Test(
        "converts an English amount with lakh or crore whole, never half in words",
        arguments: [
            ("one lakh fifty thousand rupees", .thousands, "150,000 rupees"),
            ("two lakh rupees", .thousands, "200,000 rupees"),
            ("twenty five lakh rupees", .thousands, "2,500,000 rupees"),
            ("one crore twenty lakh", .thousands, "12,000,000"),
            ("it costs one hundred fifty thousand rupees", .thousands, "it costs 150,000 rupees"),
            ("one lakh fifty thousand rupees", .indian, "1,50,000 rupees"),
            ("one crore twenty lakh", .indian, "1,20,00,000"),
            ("three lac rupees", .indian, "3,00,000 rupees"),
        ] as [(String, DigitGrouping, String)]
    )
    func indianScaleWords(input: String, grouping: DigitGrouping, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always, digits: grouping)) == expected)
    }

    @Test("groups by lakh and crore when the number style says Indian")
    func indianGrouping() {
        #expect(NumberWords.render(10_000, grouping: .indian) == "10,000")
        #expect(NumberWords.render(150_000, grouping: .indian) == "1,50,000")
        #expect(NumberWords.render(12_345_678, grouping: .indian) == "1,23,45,678")
    }

    @Test("one pipeline writes each number style from the situation alone")
    func numberStyleFromSituation() {
        let formatter = DestinationFormatter.standard(for: .plain)
        let cases: [(DigitGrouping, String)] = [(.thousands, "150,000"), (.indian, "1,50,000")]
        for (grouping, expected) in cases {
            let situation = Situation(
                app: .unknown, insertion: .unknown, destination: .plain,
                numberStyle: NumberStyle(grouping: grouping))
            let pass = NumberFormsPass(policy: formatter.numbers, digits: situation.digits(for: formatter))
            #expect(
                pass.apply(Draft(text: "we paid one hundred fifty thousand rupees")).text.contains(expected))
        }
    }

    @Test("a place that parses its digits overrides the person's grouping")
    func parsedPlaceOverridesStyle() {
        let situation = Situation(
            app: .unknown, insertion: .unknown, destination: .codeEditor,
            numberStyle: NumberStyle(grouping: .indian))
        #expect(situation.digits(for: .standard(for: .codeEditor)) == .none)
    }

    @Test("a grouping recognises only its own spellings")
    func groupingMatches() {
        #expect(DigitGrouping.indian.matches("1,50,000") && !DigitGrouping.thousands.matches("1,50,000"))
        #expect(DigitGrouping.thousands.matches("150,000") && !DigitGrouping.indian.matches("150,000"))
        #expect(!DigitGrouping.indian.matches("1,2,000") && DigitGrouping.none.matches("150000"))
    }

    // MARK: - How the digits are grouped

    /// A separator is prose's habit; Postgres reads 12,000 as a row constructor and a compiler rejects it.
    @Test(
        "writes a numeral without separators where the destination is machine-read",
        arguments: [
            ("where total is greater than twelve thousand", "where total is greater than 12000"),
            ("let limit equals twelve thousand", "let limit equals 12000"),
            ("set the cap to one million", "set the cap to 1000000"),
        ]
    )
    func writesUngroupedDigits(input: String, expected: String) {
        let sut = NumberFormsPass(policy: .always, digits: .none)
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "still groups them where the words are prose",
        arguments: [
            ("we sold twelve thousand units", "we sold 12,000 units"),
            ("the budget is one million", "the budget is 1,000,000"),
        ]
    )
    func groupsDigitsInProse(input: String, expected: String) {
        let sut = NumberFormsPass(policy: .always, digits: .thousands)
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The context word means "these digits run together", which is true whatever the destination does.
    @Test("runs a context word's digits together in either destination")
    func contextWordsStillRunTogether() {
        #expect(
            cleaned("extension four four two", by: NumberFormsPass(policy: .always, digits: .thousands))
                == cleaned("extension four four two", by: NumberFormsPass(policy: .always, digits: .none)))
    }

    @Test("groups digits unless the destination says otherwise")
    func groupingDefaultsToProse() {
        #expect(DestinationFormatter.standard(for: .plain).digits == .thousands)
        #expect(DestinationFormatter.standard(for: .document).digits == .thousands)
        #expect(DestinationFormatter.standard(for: .sqlEditor).digits == .none)
        #expect(DestinationFormatter.standard(for: .codeEditor).digits == .none)
        // A cell keeps its separators: the corpus's own reference for a spreadsheet is "12,000".
        #expect(DestinationFormatter.standard(for: .spreadsheet).digits == .thousands)
    }

    @Test(
        "writes a romanised Hindi number in digits only before an amount, unit or time word",
        arguments: [
            ("paanch sau rupaye de do", "500 rupaye de do"),
            ("do hazaar rupaye bhejo", "2000 rupaye bhejo"),
            ("do hazaar paanch sau rupaye", "2500 rupaye"),
            ("ek lakh rupaye", "100,000 rupaye"),
            ("teen crore rupees", "30,000,000 rupees"),
            ("pachas rupaye", "50 rupaye"),
            ("sau rupaye", "100 rupaye"),
            ("das kilo chawal", "10 kilo chawal"),
            ("do litre doodh", "2 litre doodh"),
            ("paanch minute ruko", "5 minute ruko"),
            ("teen ghante lagenge", "3 ghante lagenge"),
            ("chaar baje milte hain", "4 baje milte hain"),
            ("bees saal ho gaye", "20 saal ho gaye"),
            ("saat din baad", "7 din baad"),
            ("chhah mahine", "6 mahine"),
            ("do sau pachas gram", "250 gram"),
            ("pachchis tareekh ko", "25 tareekh ko"),
            ("assi paise", "80 paise"),
            ("do hafte", "2 hafte"),
            ("paanch lakh pachas hazaar rupaye", "550,000 rupaye"),
            ("main do din mein aaunga", "main 2 din mein aaunga"),
            ("do baatein karni hain", "do baatein karni hain"),
            ("hum saath chalenge", "hum saath chalenge"),
            ("paanch sau log aaye", "paanch sau log aaye"),
            ("ek baar aur", "ek baar aur"),
            ("ek, rupaye", "ek, rupaye"),
        ]
    )
    func hindiAmounts(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }

    @Test(
        "keeps a Hindi number word before a unit English shares when the sentence around it is English",
        arguments: [
            ("it costs about sau rupees each", "it costs about sau rupees each"),
            ("we need das kilo of rice", "we need das kilo of rice"),
            ("wait for paanch minute", "wait for paanch minute"),
            ("sau rupees ka hai", "100 rupees ka hai"),
            ("mujhe do kilo chahiye", "mujhe 2 kilo chahiye"),
            ("it costs sau rupaye", "it costs 100 rupaye"),
        ]
    )
    func hindiNumberInAnEnglishSentence(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass()) == expected)
    }
}
