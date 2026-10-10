// Finds a word among the live words by halving, so laying out a long message reads each word a bounded number of times.
import UttrflowCore

extension PieceJoiner {
    /// Where the word at `index` stands in `live`, the ascending positions of the words still present; nil when removed.
    static func livePosition(of index: Int, in live: [Int]) -> Int? {
        var low = 0
        var high = live.count
        while low < high {
            let middle = (low + high) / 2
            if live[middle] < index { low = middle + 1 } else { high = middle }
        }
        return low < live.count && live[low] == index ? low : nil
    }
}
