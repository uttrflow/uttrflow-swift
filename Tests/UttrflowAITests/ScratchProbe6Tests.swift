import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe6")
struct ScratchProbe6Tests {
    @Test func near() {
        let pairs = [("iOS","is a"),("iOS","I saw"),("Pytest","pie test"),("Kubelet","cube lit"),("Priya","pry a"),("Uttrflow","utter flow"),("Figma","fig ma"),("Ollama","oh llama"),("Vercel","ver sell"),("Supabase","super base"),("Nginx","engine x"),("Prisma","prism a"),("Tailwind","tail wind"),("macOS","mac o s"),("Redis","red is"),("Mira","me a"),("Ray","are a"),("Zoe","so he"),("OAuth","oh off"),("Cursor","curse her"),("Okta","oak ta"),("Helm","hell am")]
        for (a,b) in pairs { print("NEAR \(a) / \(b) near=\(PhonemeLexicon.shared.soundsNear(a, b)) same=\(PhonemeLexicon.shared.soundsSame(a, b))") }
    }
}
