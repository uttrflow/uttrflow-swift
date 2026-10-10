// Invented cases rebuilt from a live clean-up probe across six destinations, each failing when it was added.
import UttrflowCore

extension EvaluationCorpus {
    // MARK: Probe regressions. See Docs/formatting-matrix.md.

    static let probeCases: [EvaluationCase] = [
        .init(
            id: "probe-ticket-and-units", category: .everyday,
            spoken:
                "yesterday i finished proj dash one four two three and opened a p r. the p ninety five latency dropped to two hundred m s which is about three x better and i am blocked on review from priya",
            expected:
                "Yesterday I finished PROJ-1423 and opened a PR. The p95 latency dropped to 200 ms, which is about 3x better, and I am blocked on review from Priya.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Yesterday", mustEndWith: "Priya.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-retry-bullets", category: .everyday,
            spoken:
                "this change moves retry handling into the http client colon bullet point adds a max retries option bullet point respects the retry after header bullet point removes the old backoff helper new paragraph tested locally with the unit suite",
            expected:
                "This change moves retry handling into the HTTP client:\n- Adds a max retries option\n- Respects the Retry-After header\n- Removes the old backoff helper\n\nTested locally with the unit suite.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "This", mustEndWith: "suite.",
            classes: [.capitalisationAndTokens, .lists, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-backtick-identifiers", category: .everyday,
            spoken:
                "can we rename user id to account id in the billing module backtick user id backtick shows up in three places",
            expected:
                "Can we rename `user_id` to `account_id` in the billing module? `user_id` shows up in three places.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Can", mustEndWith: "places.",
            classes: [.questions, .quotesAndBrackets, .numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-short-hash", category: .technical,
            spoken: "revert a three f nine c two because it broke the nightly build",
            expected: "revert a3f9c2 because it broke the nightly build",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            destination: .terminal, mustBeginWith: "revert", mustEndWith: "build",
            classes: [.numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-repro-steps", category: .everyday,
            spoken:
                "steps to reproduce colon one open the app two press command comma three switch to the privacy tab new line expected colon the tab opens new line actual colon the app quits on mac os fourteen",
            expected:
                "Steps to reproduce:\n1. Open the app\n2. Press Command-comma\n3. Switch to the Privacy tab\nExpected: the tab opens\nActual: the app quits on macOS 14",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Steps", mustEndWith: "14",
            classes: [.capitalisationAndTokens, .numbers, .lists, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-docker-run-flags", category: .technical,
            spoken:
                "docker run dash dash rm dash p eight thousand colon eight thousand dash v tilde slash projects slash app colon slash app node colon twenty alpine",
            expected: "docker run --rm -p 8000:8000 -v ~/projects/app:/app node:20-alpine",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            destination: .terminal, mustBeginWith: "docker", mustEndWith: "node:20-alpine",
            classes: [.capitalisationAndTokens, .numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-sql-join", category: .technical,
            spoken:
                "select o dot id comma c dot name comma p dot title from orders o join customers c on c dot id equals o dot customer id join products p on p dot id equals o dot product id where o dot created at is after two thousand twenty six dash ten dash oh one",
            expected:
                "SELECT o.id, c.name, p.title\nFROM orders o\nJOIN customers c ON c.id = o.customer_id\nJOIN products p ON p.id = o.product_id\nWHERE o.created_at > '2026-10-01'",
            context: AppContext(applicationName: "Postico", bundleIdentifier: "at.eggerapps.Postico"),
            destination: .sqlEditor, mustBeginWith: "SELECT", mustEndWith: "'2026-10-01'",
            classes: [.capitalisationAndTokens, .numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-regex-pattern", category: .technical,
            spoken:
                "the pattern is caret open bracket a dash z close bracket plus at open bracket a dash z close bracket plus dollar",
            expected: "The pattern is ^[a-z]+@[a-z]+$",
            context: AppContext(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            destination: .codeEditor, mustBeginWith: "The pattern is", mustEndWith: "^[a-z]+@[a-z]+$",
            classes: [.quotesAndBrackets, .capitalisationAndTokens, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-yaml-keys", category: .technical,
            spoken:
                "set replicas colon three and image colon registry dot example dot com slash api colon one point four point two",
            expected: "Set replicas: 3 and image: registry.example.com/api:1.4.2",
            context: AppContext(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            destination: .codeEditor, mustBeginWith: "Set replicas:",
            mustEndWith: "registry.example.com/api:1.4.2",
            classes: [.capitalisationAndTokens, .numbers, .lists, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-todo-comment", category: .technical,
            spoken: "todo colon at sam replace this polling loop with a webhook once the vendor ships it",
            expected: "// TODO: @sam replace this polling loop with a webhook once the vendor ships it",
            context: AppContext(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            destination: .codeEditor, mustBeginWith: "//", mustEndWith: "it",
            classes: [.capitalisationAndTokens, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-log-call", category: .technical,
            spoken:
                "log dot info open paren quote user percent s logged in from percent s close quote comma user id comma ip close paren",
            expected: "log.info(\"user %s logged in from %s\", userId, ip)",
            context: AppContext(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            destination: .codeEditor, mustBeginWith: "log.info(\"user", mustEndWith: "ip)",
            classes: [.quotesAndBrackets, .capitalisationAndTokens, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-http-status", category: .everyday,
            spoken:
                "a post to slash api slash v two slash orders returns two oh one created and a get to the same path returns two hundred ok or four oh four",
            expected:
                "A POST to /api/v2/orders returns 201 Created, and a GET to the same path returns 200 OK or 404.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "A", mustEndWith: "404.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-version-bump", category: .everyday,
            spoken:
                "bump the client from one point four point two to one point five point zero and pin node to twenty two",
            expected: "Bump the client from 1.4.2 to 1.5.0 and pin Node to 22.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Bump", mustEndWith: "22.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-shell-pipeline", category: .technical,
            spoken:
                "cat access dot log pipe grep dash v health pipe sort pipe uniq dash c pipe sort dash r n pipe head dash twenty",
            expected: "cat access.log | grep -v health | sort | uniq -c | sort -rn | head -20",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            destination: .terminal, mustBeginWith: "cat", mustEndWith: "-20",
            classes: [.capitalisationAndTokens, .numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-dockerfile-from", category: .technical,
            spoken: "from node colon twenty dash alpine as build",
            expected: "FROM node:20-alpine AS build",
            context: AppContext(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
            destination: .codeEditor, mustBeginWith: "FROM", mustEndWith: "build",
            classes: [.capitalisationAndTokens, .numbers, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-git-commands", category: .everyday,
            spoken:
                "run git fetch then git rebase origin slash main then git push dash dash force dash with dash lease",
            expected: "Run git fetch, then git rebase origin/main, then git push --force-with-lease.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Run", mustEndWith: "--force-with-lease.",
            classes: [.capitalisationAndTokens, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-stack-frame", category: .everyday,
            spoken: "at main dot run open paren main dot go colon forty two close paren",
            expected: "at main.run(main.go:42)",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "at", mustEndWith: "main.run(main.go:42)",
            classes: [.quotesAndBrackets, .capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-protocol-names", category: .everyday,
            spoken:
                "we should keep the public api as rest with json but use g r p c between internal services o auth two for the browser and a service account for c i c d jobs the k eight s cluster stays in one region",
            expected:
                "We should keep the public API as REST with JSON, but use gRPC between internal services, OAuth 2 for the browser, and a service account for CI/CD jobs. The k8s cluster stays in one region.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "We", mustEndWith: "region.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-file-name-opening", category: .everyday,
            spoken: "config dot yaml is missing the timeout key so the client falls back to thirty seconds",
            expected: "config.yaml is missing the timeout key, so the client falls back to 30 seconds.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "config.yaml", mustEndWith: "seconds.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-bug-title", category: .everyday,
            spoken: "crash when opening settings on mac os fourteen",
            expected: "Crash when opening settings on macOS 14",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Crash", mustEndWith: "14",
            classes: [.sentenceBoundaries, .commas, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-changelog-bullets", category: .everyday,
            spoken:
                "bullet point added dark mode support for the sidebar bullet point fixed a crash when the cache is empty bullet point removed the dash dash legacy dash sync flag",
            expected:
                "- Added dark mode support for the sidebar\n- Fixed a crash when the cache is empty\n- Removed the --legacy-sync flag",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "-", mustEndWith: "flag",
            classes: [.capitalisationAndTokens, .lists, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-decision-record", category: .everyday,
            spoken:
                "we decided to store sessions in redis rather than postgres because the read volume is high and the data is disposable the trade off is that a restart logs everyone out so we will enable append only persistence",
            expected:
                "We decided to store sessions in Redis rather than Postgres because the read volume is high and the data is disposable. The trade off is that a restart logs everyone out, so we will enable append only persistence.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "We", mustEndWith: "persistence.",
            classes: [.sentenceBoundaries, .commas, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-git-commit-flags", category: .technical,
            spoken: "git commit dash dash no dash verify dash m quote wip quote",
            expected: "git commit --no-verify -m \"wip\"",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            destination: .terminal, mustBeginWith: "git", mustEndWith: "\"wip\"",
            classes: [.quotesAndBrackets, .capitalisationAndTokens, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-docker-build-no-cache", category: .technical,
            spoken: "docker build dash dash no dash cache dot",
            expected: "docker build --no-cache .",
            context: AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
            destination: .terminal, mustBeginWith: "docker", mustEndWith: ".",
            classes: [.capitalisationAndTokens, .perDestination, .codeAndMarkdown],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-spoken-correction", category: .everyday,
            spoken: "no wait thursday works better for the board",
            expected: "No wait, Thursday works better for the board.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "No", mustEndWith: "board.",
            classes: [.corrections, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-support-email", category: .everyday,
            spoken:
                "hi priya comma thanks for getting in touch about the delayed order new paragraph i have checked with our warehouse and your parcel left the depot this morning it should reach you by thursday the ninth of october new paragraph if it has not arrived by friday please reply to this email and i will send a replacement at no cost new paragraph thanks again for your patience comma new line dana",
            expected:
                "Hi Priya,\n\nThanks for getting in touch about the delayed order.\n\nI have checked with our warehouse and your parcel left the depot this morning. It should reach you by Thursday the 9th of October.\n\nIf it has not arrived by Friday, please reply to this email and I will send a replacement at no cost.\n\nThanks again for your patience,\nDana",
            context: AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail"),
            destination: .email, mustBeginWith: "Hi", mustEndWith: "Dana",
            classes: [.capitalisationAndTokens, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-laugh-then-question", category: .everyday,
            spoken:
                "ha ha that is the best excuse i have heard all week i am stealing it new line can you send me the photo of the whiteboard and put a laughing face emoji at the end",
            expected:
                "Ha ha, that is the best excuse I have heard all week. I am stealing it\nCan you send me the photo of the whiteboard and put a laughing face emoji at the end",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Ha", mustEndWith: "end",
            classes: [.capitalisationAndTokens, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-meeting-notes", category: .everyday,
            spoken:
                "meeting notes colon product sync new line action item colon priya to send the revised budget by friday the tenth of october new line action item colon omar to book the review room for the fourteenth new line decision colon we ship the beta on the twentieth and hold the announcement until the docs are ready",
            expected:
                "Meeting notes: product sync\nAction item: Priya to send the revised budget by Friday the 10th of October\nAction item: Omar to book the review room for the 14th\nDecision: we ship the beta on the 20th and hold the announcement until the docs are ready",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Meeting", mustEndWith: "ready",
            classes: [.capitalisationAndTokens, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-revenue-figures", category: .everyday,
            spoken:
                "q three revenue was one point two million dollars up eight percent on the previous quarter and churn fell from four point one percent to three point six percent we closed forty two new accounts against a target of fifty and support tickets dropped by thirty percent",
            expected:
                "Q3 revenue was $1.2 million, up 8% on the previous quarter, and churn fell from 4.1% to 3.6%. We closed 42 new accounts against a target of 50, and support tickets dropped by 30%.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Q3", mustEndWith: "30%.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-option-pricing", category: .everyday,
            spoken:
                "option a is a fixed fee of twelve thousand five hundred dollars with delivery in four weeks while option b is eighteen thousand dollars with delivery in two weeks and includes training for up to ten staff",
            expected:
                "Option A is a fixed fee of $12,500 with delivery in four weeks, while Option B is $18,000 with delivery in two weeks and includes training for up to 10 staff.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Option", mustEndWith: "staff.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-apology-message", category: .everyday,
            spoken:
                "i am so sorry about missing your call yesterday i had my phone on silent during the workshop and did not see it until late i will call you tomorrow at ten am if that works for you",
            expected:
                "I am so sorry about missing your call yesterday. I had my phone on silent during the workshop and did not see it until late. I will call you tomorrow at 10 am if that works for you.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "I", mustEndWith: "you.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-cover-letter", category: .everyday,
            spoken:
                "dear ms alvarez comma new paragraph i am writing to apply for the senior analyst position advertised on your careers page new paragraph in my current role i lead a team of six analysts and reduced reporting time by thirty percent new paragraph i would welcome the chance to discuss my application comma new line yours sincerely comma new line asha verma",
            expected:
                "Dear Ms Alvarez,\n\nI am writing to apply for the senior analyst position advertised on your careers page.\n\nIn my current role I lead a team of six analysts and reduced reporting time by 30%.\n\nI would welcome the chance to discuss my application,\nYours sincerely,\nAsha Verma",
            context: AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail"),
            destination: .email, mustBeginWith: "Dear", mustEndWith: "Verma",
            classes: [.numbers, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-meeting-time-zones", category: .everyday,
            spoken:
                "team retro on tuesday the fourteenth of october at ten thirty a m pacific time which is one thirty p m eastern join at meet dot example dot com slash retro dash team dash one two three and bring your notes",
            expected:
                "Team retro on Tuesday the 14th of October at 10:30 a.m. Pacific time, which is 1:30 p.m. Eastern. Join at meet.example.com/retro-team-123 and bring your notes.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Team", mustEndWith: "notes.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-recipe-quantities", category: .everyday,
            spoken:
                "preheat the oven to three seventy five degrees fahrenheit mix one and a half cups of flour with a quarter teaspoon of salt and bake for twenty five to thirty minutes",
            expected:
                "Preheat the oven to 375 degrees Fahrenheit. Mix one and a half cups of flour with a quarter teaspoon of salt and bake for 25 to 30 minutes.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Preheat", mustEndWith: "minutes.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-flight-details", category: .everyday,
            spoken:
                "we fly on flight u a four seven two from j f k to heathrow on friday the third of october departing at six forty five a m from gate b twelve and landing at six ten p m local time at terminal five",
            expected:
                "We fly on flight UA 472 from JFK to Heathrow on Friday the 3rd of October, departing at 6:45 a.m. from Gate B12 and landing at 6:10 p.m. local time at Terminal 5.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "We", mustEndWith: "5.",
            classes: [.capitalisationAndTokens, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-clinical-note", category: .everyday,
            spoken:
                "patient is a fifty two year old with chest tightness for two days blood pressure one forty over ninety heart rate seventy two b p m temperature ninety eight point six s p o two ninety eight percent on room air start aspirin eighty one m g by mouth once daily and recheck in two weeks",
            expected:
                "Patient is a 52 year old with chest tightness for two days. Blood pressure 140 over 90, heart rate 72 bpm, temperature 98.6, SpO2 98% on room air. Start aspirin 81 mg by mouth once daily and recheck in two weeks.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Patient", mustEndWith: "weeks.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-contract-clauses", category: .everyday,
            spoken:
                "clause nine point one the supplier shall item a deliver within thirty days of the order item b replace any damaged goods at its own cost and item c keep records for six years",
            expected:
                "Clause 9.1 The supplier shall\n(a) deliver within 30 days of the order\n(b) replace any damaged goods at its own cost and\n(c) keep records for six years.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Clause", mustEndWith: "years.",
            classes: [.capitalisationAndTokens, .numbers, .lists, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-quoted-citation", category: .everyday,
            spoken:
                "harlow argues that habits shape outcomes and writes quote small steps compound quietly unquote open parenthesis harlow nineteen ninety eight close parenthesis new line this suggests that daily practice matters more than talent",
            expected:
                "Harlow argues that habits shape outcomes and writes \"small steps compound quietly\" (Harlow 1998).\nThis suggests that daily practice matters more than talent.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Harlow", mustEndWith: "talent.",
            classes: [.quotesAndBrackets, .numbers, .paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-short-verse", category: .everyday,
            spoken:
                "roses are red new line violets are blue new line sugar is sweet new line and so are you new paragraph the moon is bright new line the stars are near new line i wish that you were here",
            expected:
                "Roses are red\nViolets are blue\nSugar is sweet\nAnd so are you.\n\nThe moon is bright\nThe stars are near\nI wish that you were here.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Roses", mustEndWith: "here.",
            classes: [.paragraphs, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-hashtag-and-handle", category: .everyday,
            spoken:
                "we are live hashtag spring launch and a big thank you to at maya underscore designs for the photos",
            expected: "We are live #springlaunch and a big thank you to @maya_designs for the photos.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "We", mustEndWith: "photos.",
            classes: [.capitalisationAndTokens, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-phone-and-address", category: .everyday,
            spoken:
                "call me on four one five five five five zero one three two or come to flat twelve b maple road springfield pin code four zero zero zero zero one after six p m",
            expected:
                "Call me on 4155550132 or come to flat 12B Maple Road, Springfield, pin code 400001 after 6 p.m.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Call", mustEndWith: "p.m.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-chained-corrections", category: .everyday,
            spoken:
                "can we meet at four no sorry at five actually make it half past six on wednesday no thursday if that suits you",
            expected: "Can we meet at half past six on Thursday if that suits you?",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "Can", mustEndWith: "you?",
            classes: [.questions, .capitalisationAndTokens, .numbers, .corrections, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-topic-shifts", category: .everyday,
            spoken:
                "so about the offsite i think we should book the venue by the end of the month um the budget is still open though and finance needs a number by friday anyway on a different note the onboarding doc is out of date so i will rewrite the first three sections this week and then ask rohit to review it oh and one more thing the printer on the second floor is jammed again",
            expected:
                "So about the offsite, I think we should book the venue by the end of the month. The budget is still open though, and finance needs a number by Friday.\n\nOn a different note, the onboarding doc is out of date, so I will rewrite the first three sections this week and then ask Rohit to review it.\n\nOh, and one more thing: the printer on the second floor is jammed again.",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "So", mustEndWith: "again.",
            classes: [.numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-hinglish-status", category: .multilingual, language: .hindi,
            spoken:
                "kal ka deployment fail ho gaya tha pipeline mein timeout aa raha hai toh pehle rollback karna padega phir api ka rate limit check karenge kya aap review kar sakte ho",
            expected:
                "Kal ka deployment fail ho gaya tha. Pipeline mein timeout aa raha hai, toh pehle rollback karna padega, phir API ka rate limit check karenge. Kya aap review kar sakte ho?",
            context: AppContext(applicationName: "Pages", bundleIdentifier: "com.apple.iWork.Pages"),
            destination: .document, mustBeginWith: "Kal", mustEndWith: "ho?",
            classes: [.sentenceBoundaries, .commas, .questions, .perDestination, .hinglish],
            origin: .reportRewrite, addedFor: 4447
        ),
        .init(
            id: "probe-quote-unquote", category: .everyday,
            spoken:
                "she called it quote the final version unquote but it still had three open comments and one missing chart so we are not ready",
            expected:
                "She called it \"the final version\" but it still had three open comments and one missing chart, so we are not ready.",
            context: AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS"),
            destination: .messaging, mustBeginWith: "She", mustEndWith: "ready.",
            classes: [.quotesAndBrackets, .numbers, .perDestination],
            origin: .reportRewrite, addedFor: 4447
        ),
    ]
}
