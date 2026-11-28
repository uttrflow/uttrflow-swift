import UttrflowCore

/// Writes spoken numbers as numerals, then an amount before a currency word as its symbol, "5 dollars" as "$5".
struct AmountFormsPass: PieceCleaningPass {
    static let id: PassID = .numberForms
    static let laws: Set<PassLaw> = NumberFormsPass.laws
    static let orderIndependentWith: Set<PassID> = NumberFormsPass.orderIndependentWith

    let numbers: NumberFormsPass

    init(policy: NumberPolicy = .fromTen, digits: DigitGrouping = .thousands) {
        numbers = NumberFormsPass(policy: policy, digits: digits)
    }

    func apply(_ draft: Draft) -> Draft {
        var draft = numbers.apply(draft)
        NumberFormsPass.writeSymbols(in: &draft)
        return draft
    }
}
