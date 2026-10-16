import Testing
@testable import UttrflowDictionary

@Suite("ScratchLearn")
struct ScratchLearnTests {
    @Test func learn() {
        let pairs = [("affect","effect"),("principal","principle"),("Smith","Smyth"),("colour","color"),("teh","the"),("recieve","receive"),("Katherine","Catherine"),("Jon","John"),("their","there"),("two","too"),("whether","weather"),("break","brake"),("Brian","Bryan"),("meet","meat"),("read","reed"),("would","wood"),("Steven","Stephen"),("Anne","Ann"),("Sara","Sarah"),("Mark","Marc"),("kubernetes","Kubernetes"),("loose","lose"),("then","than"),("accept","except"),("quiet","quite"),("cache","cash"),("bare","bear"),("Lee","Leigh"),("Pete","Peat"),("hear","here"),("you're","your"),("its","it's"),("lead","led"),("Deepa","Deepak"),("Rao","Ray"),("Nikhil","Nikhill"),("Anna","Anne"),("Tomas","Tomás"),("Zoe","Zoey")]
        for (a,b) in pairs { if let r = LearnableWords.corrected(over: a, wrote: b) { print("LEARN \(a) -> \(b) learned=\(r)") } }
    }
}
