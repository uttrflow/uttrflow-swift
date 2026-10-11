// Invented sentences holding digit strings and codes, at least ten per shape, for the digit-string probe.

/// The digit-string and code class: every value is invented, and none is a working number of any kind.
public enum DigitStringCorpus {
    /// Every case, grouped by shape.
    public static let all: [DigitStringCase] =
        longStrings + alphanumeric + ohForZero + grouped + repeated + times + yearThenNumber

    static let longStrings = cases(
        .longString,
        [
            ("your order number is four seven one nine two eight three six", ["47192836"]),
            ("the reference is eight two six four one nine three seven five", ["826419375"]),
            ("please quote tracking number three nine one seven two six four eight five one", ["3917264851"]),
            ("the invoice is numbered five two eight one six three nine four", ["52816394"]),
            ("my account ends in nine three six two seven one four eight", ["93627148"]),
            ("ticket six one eight four two nine seven three is still open", ["61842973"]),
            ("the parcel code is two four nine six one eight seven three five two", ["2496187352"]),
            ("enter the serial seven five three one eight six two four nine", ["753186249"]),
            ("the claim number is one eight six three nine two four seven", ["18639247"]),
            ("member number four one seven two nine eight six three five", ["417298635"]),
            ("the batch is three six two nine four one eight seven", ["36294187"]),
            ("transfer reference nine one four seven three eight two six five one six", ["91473826516"]),
        ])

    static let alphanumeric = cases(
        .alphanumeric,
        [
            ("our flight is Q X four one seven", ["QX417"]),
            ("the case number is C R two nine one eight", ["CR2918"]),
            ("your booking code is K seven M four P two", ["K7M4P2"]),
            ("the part is labelled B X nine three one", ["BX931"]),
            ("seat fourteen F is by the window", ["14F"]),
            ("the room is B two one four", ["B214"]),
            ("the error code is E four zero two", ["E402"]),
            ("platform nine B leaves first", ["9B"]),
            ("the voucher is Z Q eight one three seven", ["ZQ8137"]),
            ("model number T R six five zero arrives friday", ["TR650"]),
            ("the gate changed to D seventeen", ["D17"]),
            ("ship it to unit four A", ["4A"]),
        ])

    static let ohForZero = cases(
        .ohForZero,
        [
            ("the meeting is in room four oh five", ["405"]),
            ("call extension two oh seven one", ["2071"]),
            ("the code is one oh oh three", ["1003"]),
            ("we are on floor three oh", ["30"]),
            ("version two point oh shipped today", ["2.0"]),
            ("the bus is route seven oh two", ["702"]),
            ("the room is six zero nine", ["609"]),
            ("the desk number is one zero zero four", ["1004"]),
            ("try code nine oh eight one", ["9081"]),
            ("the locker is five oh six", ["506"]),
            ("press oh eight to continue", ["08"]),
            ("the lab is in building two oh one", ["201"]),
        ])

    static let grouped = cases(
        .grouped,
        [
            ("the number is four five six, seven eight nine", ["456789"]),
            ("the reference is forty two, seventeen, eighty eight", ["421788"]),
            ("the code is twelve thirty four", ["1234"]),
            ("quote three one four, one five nine", ["314159"]),
            ("the order is sixty one, twenty three, ninety", ["612390"]),
            ("the batch number is eight one, five two, seven three", ["815273"]),
            ("the serial is nine nine one, two eight four", ["991284"]),
            ("the voucher is fifty five, eighteen", ["5518"]),
            ("the ticket is two seven three, six four one, nine", ["2736419"]),
            ("the policy number is thirty one, forty six, seventy two", ["314672"]),
            ("the reference reads seven seven two, four one three", ["772413"]),
        ])

    static let repeated = cases(
        .repeated,
        [
            ("the example pin is one two three four", ["1234"]),
            ("the default code is zero zero zero zero", ["0000"]),
            ("the room is double seven three", ["773"]),
            ("the room code is triple nine", ["999"]),
            ("the order is four four four one", ["4441"]),
            ("the code is double oh four", ["004"]),
            ("the batch is eight eight two two", ["8822"]),
            ("the locker is triple one", ["111"]),
            ("the reference is five five five three", ["5553"]),
            ("the gate is double two", ["22"]),
            ("the voucher is six six six nine nine", ["66699"]),
            ("the unit is three three", ["33"]),
        ])

    static let times = cases(
        .time,
        [
            ("the call is at seven forty five", ["7:45"]),
            ("we meet at ten thirty tomorrow", ["10:30"]),
            ("the train leaves at six fifteen", ["6:15"]),
            ("lunch is at twelve fifty", ["12:50"]),
            ("the alarm is set for five oh five", ["5:05"]),
            ("the class starts at nine twenty", ["9:20"]),
            ("the shop opens at eight fifty five", ["8:55"]),
            ("the bus comes at four ten", ["4:10"]),
            ("the review moved to two forty", ["2:40"]),
            ("dinner is at seven thirty five", ["7:35"]),
            ("the flight lands at eleven twenty five", ["11:25"]),
        ])

    static let yearThenNumber = cases(
        .yearThenNumber,
        [
            ("in twenty twenty four we shipped three hundred units", ["2024", "300"]),
            ("by twenty nineteen the team had forty two people", ["2019", "42"]),
            ("in nineteen ninety eight the shop sold sixty bikes", ["1998", "60"]),
            ("twenty twenty one brought fifteen new stores", ["2021", "15"]),
            ("in twenty twenty three the library added eighty shelves", ["2023", "80"]),
            ("since twenty eighteen we have run twelve trials", ["2018", "12"]),
            ("in twenty twenty two the club had ninety members", ["2022", "90"]),
            ("by twenty thirty the plan needs two hundred rooms", ["2030", "200"]),
            ("in two thousand and nine the farm planted fifty trees", ["2009", "50"]),
            ("in twenty twenty five there were thirty six entries", ["2025", "36"]),
            ("in nineteen eighty five the town built eleven bridges", ["1985", "11"]),
        ])

    /// Cases of one shape, numbered in order so an identifier names its shape and its row.
    private static func cases(_ shape: DigitShape, _ rows: [(String, [String])]) -> [DigitStringCase] {
        rows.enumerated().map { index, row in
            DigitStringCase(id: "\(shape.rawValue)-\(index + 1)", shape: shape, spoken: row.0, spans: row.1)
        }
    }
}
