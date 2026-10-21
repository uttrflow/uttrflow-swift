import UttrflowCore

extension NumberFormsPass {
    /// Whether the number at `position` follows another number with nothing between, so it goes on a run of numbers.
    static func continuesACount(at position: Int, keys: [String], shapes: [WordShape]) -> Bool {
        position > 0 && shapes[position - 1].suffix.isEmpty && shapes[position].prefix.isEmpty
            && NumberWords.isNumber(keys[position - 1])
    }
}
