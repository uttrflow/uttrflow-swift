import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe3")
struct ScratchProbe3Tests {
    static let words = ["Snowflake", "Tailwind", "Databricks", "Supabase", "Notebook", "Textbook", "Bookmark", "Headspace", "Airtable", "Quickbooks", "Mailchimp", "Dropbox", "Hubspot", "Basecamp", "Shopify", "Webflow", "Pinecone", "Redshift", "Datadog", "Sendgrid", "Zapier", "Calendly", "Typeform", "Lattice", "Retool", "Gitlab", "Sentry", "Fastly", "Cloudflare", "Heroku", "Netlify", "Clerk", "Resend", "Drizzle", "Prisma", "Svelte", "Remix", "Astro", "Vite", "Bun", "Deno", "Zig", "Elixir", "Phoenix", "Rails", "Laravel", "Spring", "Quarkus", "Kotlin", "Dart", "Go"]
    static let index = PhoneticIndex(entries: words.map { DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0)) })
    static let sentences = [
        "A single snow flake landed on my sleeve this morning",
        "The tail wind pushed the plane ahead of schedule",
        "Please read the text book before the exam on friday",
        "Put a book mark on page forty two for me",
        "Head space matters when you are tired and busy",
        "The mail chimp in the zoo escaped its cage",
        "Leave it in the drop box by the front door",
        "Set up base camp before it gets dark tonight",
        "The pine cone fell from the tall tree outside",
        "The red shift of distant galaxies is well known",
        "A watch dog barked at the sent grid of wires",
        "The sentry at the gate checked every pass",
        "The fast ly written note was hard to read",
        "The cloud flare of the lightning lit the sky",
        "The hero cu was a bright color",
        "The net lie fied forecast was wrong",
        "A clerk at the bank counted the drizzle of coins",
        "Prism a light through the glass to see it split",
        "A spring in the step and a phoenix on the flag",
        "The rails of the old train and the lat ice work",
        "The sweat of the vet and the kotlin of the dart",
        "Please go to the zig zag road then deno minate it",
        "I will bun the bread and vite the guests",
        "Make a quick book of notes at the note book store",
        "The type form of the letter and the sales force",
    ]
    @Test func phrases() {
        let e = WordCorrectionEngine()
        for s in Self.sentences {
            for ctx in [AppContext.unknown, CorrectionFixtures.showing(Self.words.joined(separator: " "))] {
                let p = e.proposals(for: CorrectionFixtures.doubting(s), against: Self.index, seeing: ctx)
                if !p.isEmpty { print("PHRASE screen=\(ctx != .unknown) | \(s) -> \(p.map { "\($0.heard)=>\($0.replacement) [\($0.reason)]" })") }
            }
        }
    }
}
