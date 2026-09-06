import UttrflowEval
import UttrflowPredict

extension FixtureCatalogue {
    /// Two formal replies, where the openers and closers are set phrases and the middle is anything in register.
    static let mail: [Scenario] = [
        mail(
            "invoice", subject: "Re: August invoice",
            thread:
                "From: Sam\nHi, could you share the invoice for August when you get a chance? Thanks, Sam",
            own: [
                "Please find the document attached.", "Let me know if anything else is needed.",
                "Best regards,",
                "Thank you for your patience.",
            ],
            lines: [
                Line("Please find the invoice attached.", determinacy: .prose),
                Line("Let me know if anything else is needed.", determinacy: .prose),
                Line("Thank you for your patience.", determinacy: .prose),
                Line("Apologies for the delay.", determinacy: .prose),
                Line("Best regards,", determinacy: .prose),
                Line("Kind regards,", determinacy: .prose), "I hope this helps.",
                "Attached is the August invoice.",
                "Happy to walk you through it on a call.",
                Line("Looking forward to hearing from you.", determinacy: .prose),
                "The updated invoice is attached.", "Do let me know if you need anything else.",
                Line("Warm regards,", determinacy: .prose),
            ]),
        mail(
            "plumber", subject: "Re: Kitchen tap",
            thread:
                "From: Meera\nHi, the plumber can come Thursday morning or Friday afternoon. Which works for you?",
            own: [
                "Thursday morning works for me.", "Thanks for arranging this.", "Best,",
                "Could you confirm the time?",
            ],
            lines: [
                "Thursday morning works for me.",
                Line("Thanks for arranging this so quickly.", determinacy: .prose),
                Line("Could you confirm the time, please?", determinacy: .prose), "I will be home from 9.",
                "Friday afternoon is better for me.",
                Line("Please let me know if that changes.", determinacy: .prose),
                Line("Many thanks,", determinacy: .prose), Line("Best wishes,", determinacy: .prose),
                Line("Sorry for the late reply.", determinacy: .prose), "I appreciate your help with this.",
                "I will be out on Thursday afternoon.", Line("Thanks again,", determinacy: .prose),
            ]),
    ]

    /// A mail reply: the quoted message beside the body, how this person writes replies, the sender line barred.
    static func mail(
        _ name: String, subject: String, thread: String, own: [String], lines: [Line]
    ) -> Scenario {
        Scenario(
            category: "mail", name: name,
            situation: GenerationSituation(
                application: "Mail", field: "Message body", windowTitle: subject, surroundings: thread,
                recentLines: own, isMultiline: true),
            cuts: .prose, determinacy: .any, band: 1...120,
            forbidden: ScreenThread.labels(in: thread) + ScreenThread.snippets(in: thread), lines: lines)
    }
}
