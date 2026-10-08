#!/usr/bin/env python3
# Builds the synthetic dictation corpus, writes jobs for `uttrflow-dev bench`, and scores a run. See Docs/performance.md.
import argparse, array, hashlib, json, math, os, random, re, statistics, subprocess, sys, unicodedata, wave
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, ".build", "bench")
ENGLISH = ["Samantha", "Daniel", "Rishi"]  # US, UK and Indian English
# Every voice the corpus may use, and where it comes from; Docs/performance-dictation.md states the licence.
VOICE_SOURCES = {voice: "macOS system voice" for voice in ENGLISH + ["Lekha"]}
# Words per minute for the speed variants; `say` reads at about 175 by default.
RATES = {"slow": 130, "fast": 240}
PAUSE = " [[slnc 900]] "

POOL = [
    "The garden needs water before noon.", "Please send the draft to the design team by Friday.",
    "We moved the weekly meeting to the small room on the third floor.",
    "The blue folder holds last month's invoices and the new supplier list.",
    "Remind me to call the plumber about the kitchen sink tomorrow morning.",
    "The train was late again, so the workshop started twenty minutes behind schedule.",
    "Add three boxes of paper clips and a stapler to the office order.",
    "The report says sales grew slowly in the spring and faster over the summer.",
    "Can you check whether the projector in the main hall still works?",
    "The recipe calls for two cups of flour, one egg and a pinch of salt.",
    "Our flight lands at seven, and the hotel is a short taxi ride away.",
    "The new version fixes the crash when the window is resized quickly.",
    "Let's review the budget next Tuesday after lunch.",
    "The children painted the fence bright yellow over the long weekend.",
    "Water the tomatoes, feed the cat, and lock the back door before leaving.",
    "The library closes early on public holidays, so plan your visit around that.",
    "He wrote the whole chapter in one sitting and then rewrote the ending twice.",
    "The bakery on the corner sells fresh bread until the early afternoon.",
    "We need a volunteer to take notes during the quarterly planning session.",
    "The storm knocked out power for most of the street for about an hour.",
    "Bring a warm jacket, because the evening wind near the lake gets very cold.",
    "The package should arrive on Thursday unless the courier is delayed again.",
    "Please rename the file so the date comes first and the project name second.",
    "The museum added a new wing for modern sculpture and old maps.",
    "The team agreed to ship the smaller change first and measure the result.",
    "I think the onboarding checklist is too long for people who only need read access.",
    "Could you move the design review to Thursday so the contractors can join?",
    "The dashboard loads slowly on older laptops, and the charts flicker when you scroll.",
    "Nobody has touched the backup script in months, which worries me a little.",
    "Let's keep the release notes short and link to the longer guide instead.",
    "The printer on the second floor jams whenever someone uses the thick card stock.",
    "I would rather fix the flaky test properly than retry it three times.",
    "The quarterly survey closes on Monday, so please remind your teams today.",
    "We should archive the old channels before the new members arrive next week.",
    "The heating in the east wing turns on too early and wastes a lot of energy.",
    "Please double check the shipping address before you confirm the order.",
    "The interns finished the prototype early and started writing documentation.",
    "Our support queue doubled after the update, mostly with questions about login.",
    "I left the spare keys with the front desk in a small brown envelope.",
    "The workshop ran long, but everyone agreed the second half was worth it.",
]

REPLIES = [("Okay", "Okay."), ("Thank you", "Thank you."), ("Sounds good", "Sounds good."),
           ("Call me back", "Call me back."), ("Ship it", "Ship it."), ("Not today", "Not today."),
           ("See you tomorrow", "See you tomorrow."), ("Yes please", "Yes please."),
           ("Are you free?", "Are you free?"), ("What time?", "What time?"), ("Really?", "Really?"),
           ("Can you call me?", "Can you call me?"), ("Almost done.", "Almost done."),
           ("Running late, sorry.", "Running late, sorry.")]
HINDI_REPLIES = [
    ("हाँ ठीक है।", "Haan thik hai."),
    ("हाँ जी।", "Haan ji."),
    ("मैं आ रहा हूँ।", "Main aa raha hoon."),
    ("धन्यवाद।", "Dhanyavaad."),
    ("नहीं।", "Nahi."),
    ("ठीक है।", "Thik hai."),
    ("अच्छा ठीक है।", "Accha thik hai."),
    ("कोई बात नहीं।", "Koi baat nahi."),
    ("बस पाँच मिनट।", "Bas paanch minute."),
    ("चलो ठीक है, कल मिलते हैं।", "Chalo thik hai, kal milte hain."),
]

NUMBERS = [
    "The invoice comes to 4,250 dollars and 75 cents, due on the 12th of March.",
    ("Our conversion rate went from 3.5 percent to 4.2 percent in 6 weeks.",
     "Our conversion rate went from 3.5% to 4.2% in 6 weeks."),
    "Set the timeout to 250 milliseconds and retry 3 times before failing.",
    "The meeting starts at 9:45 and the flight number is 447.",
]
EMAILS = [
    ("Please send the contract to priya dot shah at example dot com by tonight.",
     "Please send the contract to priya.shah@example.com by tonight."),
    ("My work address is ops dash team at mail dot example dot org.", "My work address is ops-team@mail.example.org."),
    ("Forward the logs to support at example dot com and copy j dot rivera at example dot net.",
     "Forward the logs to support@example.com and copy j.rivera@example.net."),
]
CODE = [
    ("Rename the function get user by ID to fetch user and update every call site.",
     "Rename the function getUserById to fetchUser and update every call site."),
    ("Set max retries to five in the config file and restart the worker.",
     "Set max_retries to 5 in the config file and restart the worker."),
    ("The bug is in parse JSON response, which returns null when the array is empty.",
     "The bug is in parseJsonResponse, which returns null when the array is empty."),
    ("Run npm install, then open source slash app dot tsx and check the use effect hook.",
     "Run npm install, then open src/app.tsx and check the useEffect hook."),
]
# Invented developer speech: commands, flags, file names, acronyms and project names, none of them real.
DEVSPEECH = [
    ("Run git rebase dash dash continue, then push the branch to origin.",
     "Run git rebase --continue, then push the branch to origin."),
    ("Open config slash settings dot yaml and set the log level to debug.",
     "Open config/settings.yaml and set the log level to debug."),
    ("The CI job fails because the API returns a four oh four for the JSON endpoint.",
     "The CI job fails because the API returns a 404 for the JSON endpoint."),
    ("Ask the Brindlecove team to bump Quorvex to version two point three.",
     "Ask the Brindlecove team to bump Quorvex to version 2.3."),
    ("Run make lint with dash v and paste the output into the PR description.",
     "Run make lint with -v and paste the output into the PR description."),
    ("Add a test for the SQL migration in the tests folder and rerun swift test.",
     "Add a test for the SQL migration in the tests folder and rerun swift test."),
]
DEVSPEECH_VOCABULARY = ["Brindlecove", "Quorvex"]
# Developer vocabulary, one short phrase per case, scored per category. Each phrase is read bare and again after
# CONTEXT_LEAD, so the two runs are a paired comparison of what preceding words do for recognition. Invented
# project names only; command, flag and acronym names are generic.
DEVVOCAB = {
    "commands": [("git push", "git push"), ("git pull", "git pull"), ("git stash pop", "git stash pop"),
                 ("npm run build", "npm run build"), ("make test", "make test"), ("cd source", "cd source"),
                 ("git rebase main", "git rebase main"), ("swift build", "swift build")],
    "flags": [("dash dash force", "--force"), ("dash dash verbose", "--verbose"), ("dash v", "-v"),
              ("dash dash dry run", "--dry-run"), ("dash dash help", "--help"), ("dash r", "-r"),
              ("dash dash no cache", "--no-cache"), ("dash dash all", "--all")],
    "tools": [("grep", "grep"), ("curl", "curl"), ("sed", "sed"), ("cargo", "cargo"), ("pip", "pip"),
              ("tmux", "tmux"), ("jq", "jq"), ("vim", "vim")],
    "acronyms": [("the API", "the API"), ("the JSON", "the JSON"), ("the CLI", "the CLI"), ("the SSH key", "the SSH key"),
                 ("the YAML file", "the YAML file"), ("the HTTP header", "the HTTP header"), ("the SDK", "the SDK"),
                 ("the PR", "the PR")],
}
DEVVOCAB_MIN_CASES = 8
CONTEXT_LEAD = {"commands": "In the terminal, run", "flags": "Then add the flag", "tools": "Pipe the output through",
                "acronyms": "Next, open"}
NOUNS = [
    ("Zorvane Kelthmar will meet Pravix and Quennel at the Velbrook office on Friday.",
     ["Zorvane", "Kelthmar", "Pravix", "Quennel", "Velbrook"]),
    ("Ask Mirvella Ostrander whether the Tashiro account moved to Dorimat last week.",
     ["Mirvella", "Ostrander", "Tashiro", "Dorimat"]),
    ("The Jaxvale release depends on Brunmore, so tell Cendrik before we ship Fyloria.",
     ["Jaxvale", "Brunmore", "Cendrik", "Fyloria"]),
]
HINGLISH = [
    "Kal ki meeting cancel ho gayi hai, toh hum report Monday ko bhejenge.",
    "Yaar, mera laptop bahut slow chal raha hai, kya tum IT team ko ticket bhej sakte ho?",
    "Aaj office mein bahut kaam hai, lekin shaam ko main gym zaroor jaunga.",
]
CODE_SWITCH_ENGLISH = "Okay team, quick update on the release today."
CODE_SWITCH_HINDI = "कल मैं ऑफिस नहीं आऊँगा, घर से काम करूँगा, और शाम तक रिपोर्ट भेज दूँगा।"
CODE_SWITCH_ROMANISED = "Kal main office nahi aaunga, ghar se kaam karunga, aur shaam tak report bhej dunga."
CODE_SWITCH_HI_EN_HINDI = "तुम्हारा लैपटॉप कहाँ है?"
CODE_SWITCH_HI_EN_ROMANISED = "Tumhara laptop kahan hai?"
CODE_SWITCH_HI_EN_ENGLISH = "The server is running slowly again today."
PUNCTUATION = [
    ("Dear team comma the build is green full stop", "Dear team, the build is green."),
    ("Can you join the call at noon question mark", "Can you join the call at noon?"),
    ("Buy milk comma eggs comma and bread new line call the landlord", "Buy milk, eggs, and bread\nCall the landlord"),
]
CORRECTIONS = [
    ("Let's meet at four no sorry at five on Thursday.", "Let's meet at five on Thursday."),
    ("Send the file to Marta, I mean to Joanna, before lunch.", "Send the file to Joanna before lunch."),
    ("Um so I think uh we should ship the smaller fix first.", "So I think we should ship the smaller fix first."),
    ("Book a table for six, actually eight, at the usual place.", "Book a table for eight at the usual place."),
]
# What the product should write where it differs from what was read: fillers are removed, the words kept.
WRITTEN_EDITS = {"en-restarts": [("and, um, nobody", "and nobody")]}
# Spellings that are equally right, offered as alternative references instead of editing a reference.
SPELLING_VARIANTS = [("card stock", "cardstock")]
VARIANT_BASES = ["d15-samantha", "d15-daniel", "d15-rishi", "d30-samantha", "reply1-daniel", "reply4-daniel",
                 "numbers1-daniel", "code0-samantha", "devspeech0-rishi", "devspeech2-daniel", "tc-en-people-rishi", "tc-hi-everyday-lekha"]


def passage(seconds, start, paused):
    """Sentences from the pool until the passage reads for about `seconds`, with a breath every third sentence."""
    chosen, words, i = [], 0, start
    while words < int(seconds * 2.75):
        chosen.append(POOL[i % len(POOL)]); words += len(POOL[i % len(POOL)].split()); i += 1
    said = "".join(s + (PAUSE if paused and k % 3 == 2 and k < len(chosen) - 1 else " ") for k, s in enumerate(chosen))
    return said.strip(), " ".join(chosen)


def committed_passages():
    """The committed TranscriptionCorpus passages, read out of the Swift source."""
    src = open(os.path.join(ROOT, "Sources", "UttrflowEval", "TranscriptionCorpus.swift")).read()

    def literal(text):
        lines = text.split("\n")[1:-1]
        indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
        return "\n".join(l[indent:] for l in lines).replace("\\\n", "").replace("\\'", "'")

    found = []
    for m in re.finditer(r'\.init\(\s*id: "([^"]+)", language: \.(\w+), stressor: \.(\w+),(.*?)\n        \)', src, re.S):
        fields = {f: literal(x.group(1)) for f in ("romanised", "devanagari")
                  for x in [re.search(f + r': (""".*?""")', m.group(4), re.S)] if x}
        found.append(dict(id=m.group(1), language=m.group(2), stressor=m.group(3), **fields))
    return found


def written_for(case_id, text):
    """The text the product should write for a committed passage, after its listed edits."""
    for read, written in WRITTEN_EDITS.get(case_id, []):
        if read not in text:
            raise ValueError(f"{case_id}: {read!r} is not in the passage")
        text = text.replace(read, written)
    return text


def clips():
    out = []

    def add(cid, category, language, voice, say, written, spoken=None, vocabulary=(), devanagari=None,
            languages=None, parts=None, rate=None):
        clip = dict(id=cid, category=category, language=language, voice=voice, say=say, spoken=spoken or say,
                    written=written, vocabulary=list(vocabulary), variant="clean", devanagari=devanagari)
        if languages is not None: clip["languages"] = languages
        if parts is not None: clip["parts"] = parts
        if rate is not None: clip["rate"] = rate
        out.append(clip)

    for i, (said, written) in enumerate(REPLIES):
        add(f"reply{i}-{ENGLISH[i % 3].lower()}", "reply", "english", ENGLISH[i % 3], said, written)
    for i, (said, written) in enumerate(HINDI_REPLIES):
        add(f"hi-reply{i}-lekha", "hi-reply", "hindi", "Lekha", said, written,
            spoken=written, devanagari=said)
        out[-1]["languages"] = ["hi"]
    for seconds in (5, 15, 30, 60, 120):
        for k, voice in enumerate(ENGLISH):
            said, written = passage(seconds, 7 * k + seconds, paused=seconds >= 30)
            add(f"d{seconds}-{voice.lower()}", f"dur{seconds}", "english", voice, said, written, spoken=written)
    said, written = passage(60, 3, paused=False)
    add("d60-nopause-samantha", "dur60", "english", "Samantha", said, written, spoken=written)
    for name, rows in (("numbers", NUMBERS), ("emails", EMAILS), ("code", CODE), ("punctuation", PUNCTUATION),
                       ("selfcorrection", CORRECTIONS)):
        for i, row in enumerate(rows):
            said, written = (row, row) if isinstance(row, str) else row
            add(f"{name}{i}-{ENGLISH[i % 3].lower()}", name, "english", ENGLISH[i % 3], said, written)
    for i, (said, written) in enumerate(DEVSPEECH):
        for voice in ENGLISH:
            add(f"devspeech{i}-{voice.lower()}", "devspeech", "english", voice, said, written,
                vocabulary=DEVSPEECH_VOCABULARY)
        for name, rate in RATES.items():
            add(f"devspeech{i}-samantha-{name}", f"devspeech-{name}", "english", "Samantha", said, written,
                vocabulary=DEVSPEECH_VOCABULARY, rate=rate)
    for kind, rows in DEVVOCAB.items():
        if len(rows) < DEVVOCAB_MIN_CASES:
            raise ValueError(f"devvocab {kind}: {len(rows)} cases, fewer than {DEVVOCAB_MIN_CASES}")
        lead = CONTEXT_LEAD[kind]
        for i, (said, written) in enumerate(rows):
            for voice in ENGLISH:
                for context, s, w in (("bare", said, written), ("context", f"{lead} {said}.", f"{lead} {written}.")):
                    add(f"devvocab-{kind}{i}-{voice.lower()}-{context}", f"devvocab-{kind}", "english", voice, s, w)
                    out[-1].update(context=context, term=written)
    for i, (said, words) in enumerate(NOUNS):
        for voice in ENGLISH:
            add(f"nouns{i}-{voice.lower()}", "nouns", "english", voice, said, said)
            add(f"nouns{i}-{voice.lower()}-vocabulary", "nouns-vocabulary", "english", voice, said, said, vocabulary=words)
    for i, said in enumerate(HINGLISH):
        add(f"hinglish{i}-rishi", "hinglish-latin", "hinglish", "Rishi", said, said)
    english_twice = f"{CODE_SWITCH_ENGLISH} {CODE_SWITCH_ENGLISH}"
    add("code-switch-en-hi-rishi-lekha", "code-switch", "hinglish", "Rishi+Lekha",
        f"{english_twice} {CODE_SWITCH_HINDI}", f"{english_twice} {CODE_SWITCH_ROMANISED}",
        spoken=f"{english_twice} {CODE_SWITCH_ROMANISED}",
        devanagari=f"{english_twice} {CODE_SWITCH_HINDI}", languages=["en", "hi"],
        parts=[["Rishi", f"{CODE_SWITCH_ENGLISH}{PAUSE}{CODE_SWITCH_ENGLISH}"], ["Lekha", CODE_SWITCH_HINDI]])
    add("code-switch-hi-en-lekha-rishi", "code-switch", "hinglish", "Lekha+Rishi",
        f"{CODE_SWITCH_HI_EN_HINDI}{PAUSE}{CODE_SWITCH_HI_EN_ENGLISH}",
        f"{CODE_SWITCH_HI_EN_ROMANISED} {CODE_SWITCH_HI_EN_ENGLISH}",
        spoken=f"{CODE_SWITCH_HI_EN_ROMANISED} {CODE_SWITCH_HI_EN_ENGLISH}",
        devanagari=f"{CODE_SWITCH_HI_EN_HINDI} {CODE_SWITCH_HI_EN_ENGLISH}", languages=["hi", "en"],
        parts=[["Lekha", CODE_SWITCH_HI_EN_HINDI], ["Rishi", CODE_SWITCH_HI_EN_ENGLISH]])
    for case in committed_passages():
        if case["language"] == "english":
            for voice in ENGLISH:
                add(f"tc-{case['id']}-{voice.lower()}", f"tc-{case['stressor']}", "english", voice,
                    case["romanised"], written_for(case["id"], case["romanised"]), spoken=case["romanised"])
        else:
            add(f"tc-{case['id']}-lekha", f"tc-{case['language']}", case["language"], "Lekha", case["devanagari"],
                case["romanised"], spoken=case["romanised"], devanagari=case["devanagari"])
    return out


def read_wav(path):
    w = wave.open(path); samples = array.array("h", w.readframes(w.getnframes())); w.close(); return samples


def write_wav(path, samples):
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(samples.tobytes()); w.close()


def render_clip(clip):
    if not clip.get("parts"):
        rate = ["-r", str(clip["rate"])] if clip.get("rate") else []
        subprocess.run(["say", "-v", clip["voice"], *rate, "-o", clip["wav"], "--file-format=WAVE",
                        "--data-format=LEI16@16000", clip["say"]], check=True)
        return
    joined = array.array("h")
    for index, (voice, said) in enumerate(clip["parts"]):
        base, extension = os.path.splitext(clip["wav"])
        part = f"{base}-part{index}{extension}"
        if not os.path.exists(part):
            subprocess.run(["say", "-v", voice, "-o", part, "--file-format=WAVE",
                            "--data-format=LEI16@16000", said], check=True)
        if index: joined.extend([0] * 24000)  # The language switch follows 1.5 seconds of silence.
        joined.extend(read_wav(part))
    write_wav(clip["wav"], joined)


AR1_COEFFICIENT = 0.97
# The steady-state standard deviation of `level = AR1_COEFFICIENT * level + N(0, 1)`, so the
# raw AR(1) sequence can be rescaled to a chosen standard deviation rather than assumed unit.
AR1_STD = 1 / math.sqrt(1 - AR1_COEFFICIENT**2)


def noisy(snr_db, seed):
    """Brown noise mixed in at exactly `snr_db` below the speech's RMS power."""
    def mix(samples):
        rng = random.Random(seed)
        power = sum(x * x for x in samples) / max(1, len(samples))
        target_std = math.sqrt(power / (10 ** (snr_db / 10)))
        scale = target_std / AR1_STD
        out, level, clipped = array.array("h"), 0.0, 0
        for x in samples:
            level = AR1_COEFFICIENT * level + rng.gauss(0, 1)
            mixed = x + level * scale
            if mixed > 32767 or mixed < -32768:
                clipped += 1
            out.append(max(-32768, min(32767, int(mixed))))
        if clipped:
            print(f"noisy: {clipped} of {len(samples)} sample(s) clipped mixing snr {snr_db} dB", file=sys.stderr)
        return out
    return mix


def gain(db):
    k = 10 ** (db / 20)
    return lambda samples: array.array("h", (max(-32768, min(32767, int(x * k))) for x in samples))


def corpus(args):
    audio = os.path.join(args.out, "audio"); os.makedirs(audio, exist_ok=True)
    made = clips()
    unlisted = sorted({v for c in made for v in c["voice"].split("+")} - VOICE_SOURCES.keys())
    if unlisted:
        sys.exit(f"voices without a recorded source and licence: {', '.join(unlisted)}")
    for c in made:
        # Named by what was spoken, by whom and how fast, so a changed passage, voice or rate is spoken again.
        rate = f"\n{c['rate']}" if c.get("rate") else ""
        spoken = hashlib.sha256(f"{c['voice']}\n{c['say']}\nLEI16@16000{rate}".encode()).hexdigest()[:12]
        c["wav"] = os.path.join(audio, f"{c['id']}-{spoken}.wav")
        if not os.path.exists(c["wav"]):
            render_clip(c)
    for c in [c for c in made if c["id"] in VARIANT_BASES]:
        for name, change in (("snr20", noisy(20, 1)), ("snr10", noisy(10, 2)), ("quiet", gain(-24)), ("hot", gain(12))):
            v = dict(c, id=f"{c['id']}-{name}", variant=name, wav=c["wav"].replace(".wav", f"-{name}.wav"))
            if not os.path.exists(v["wav"]):
                write_wav(v["wav"], change(read_wav(c["wav"])))
            made.append(v)
    for c in made:
        w = wave.open(c["wav"]); c["duration"] = w.getnframes() / w.getframerate(); w.close()
    json.dump(made, open(os.path.join(args.out, "corpus.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{len(made)} clips, {sum(c['duration'] for c in made) / 60:.1f} min of speech, in {args.out}")


def jobs(args):
    made = json.load(open(os.path.join(args.out, "corpus.json")))
    chosen = [c for c in made if not args.categories or c["category"] in args.categories.split(",")]
    if args.clean_only:
        chosen = [c for c in chosen if c["variant"] == "clean"]
    if not chosen:
        sys.exit(f"--categories {args.categories!r} selected no clips out of {len(made)} in the corpus")
    cleaners = args.cleaners.split(",")
    if not set(cleaners) <= {"shipping", "rules"}:
        sys.exit(f"--cleaners takes shipping and rules, not {args.cleaners}")
    lines = []
    for _ in range(args.repeat):
        for c in chosen:
            for cleaner in cleaners:
                fields = [c["id"], c["wav"], ",".join(c["vocabulary"]), args.mode, cleaner]
                if c.get("languages"): fields.append(",".join(c["languages"]))
                lines.append("\t".join(fields))
    if not lines:
        sys.exit(f"selected {len(chosen)} clip(s) but --repeat {args.repeat} produced no jobs")
    sys.stdout.write("\n".join(lines) + "\n")


NORMALISED = {}


def eval_tool():
    """The `uttrflow-eval` binary that owns the word-normalisation rule; UTTRFLOW_EVAL overrides the path."""
    candidates = [os.environ.get("UTTRFLOW_EVAL")] + [os.path.join(ROOT, ".build", c, "uttrflow-eval")
                                                       for c in ("release", "debug")]
    found = next((c for c in candidates if c and os.access(c, os.X_OK)), None)
    if not found:
        sys.exit("no uttrflow-eval binary: run swift build -c release --product uttrflow-eval, or set UTTRFLOW_EVAL")
    return found


def normalise_all(texts):
    """Normalises every text not yet seen in one call to `uttrflow-eval normalise`, the rule every scorer shares."""
    fresh = sorted({" ".join(t.split()) for t in texts} - NORMALISED.keys())
    if fresh:
        run = subprocess.run([eval_tool(), "normalise"], input="\n".join(fresh) + "\n",
                             capture_output=True, text=True, check=True)
        lines = run.stdout.split("\n")[:len(fresh)]
        if len(lines) != len(fresh):
            sys.exit(f"uttrflow-eval normalise answered {len(lines)} lines for {len(fresh)} texts")
        NORMALISED.update(zip(fresh, (line.split() for line in lines)))
    return [NORMALISED[" ".join(t.split())] for t in texts]


def normalise(text):
    """The words a word error rate is counted over; see TextNormaliser in Sources/UttrflowEval."""
    return normalise_all([text])[0]


def normalisation_rules():
    """The rules in force, printed beside every score so runs under different rules are not compared."""
    return subprocess.run([eval_tool(), "normalise", "--rules"], capture_output=True, text=True, check=True).stdout.strip()


def edits(ref, hyp):
    row = list(range(len(hyp) + 1))
    for i in range(1, len(ref) + 1):
        prev, row[0] = row[:], i
        for j in range(1, len(hyp) + 1):
            row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (ref[i - 1] != hyp[j - 1]))
    return row[len(hyp)]


def with_spelling_variants(references):
    """Each reference, plus each of its spellings from SPELLING_VARIANTS."""
    out = [r for r in references if r]
    for a, b in SPELLING_VARIANTS:
        for r in list(out):
            for x, y in ((a, b), (b, a)):
                changed = re.sub(rf"(?i)\b{re.escape(x)}\b", y, r)
                if changed != r and changed not in out: out.append(changed)
    return out


def exact_words(text):
    """Words as written, case, marks and symbols kept, so a wrong capital or symbol is an error."""
    return unicodedata.normalize("NFC", text).split()


def errors(references, hypothesis, words=normalise):
    """The fewest edits against any of the references, with that reference's length."""
    h = words(hypothesis)
    scored = [(edits(words(r), h), len(words(r))) for r in with_spelling_variants(references)]
    return min(scored, key=lambda x: x[0] / max(1, x[1]))


def percentile(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))] if values else float("nan")


def score(args):
    made = {c["id"]: c for c in json.load(open(os.path.join(args.out, "corpus.json")))}
    rows, unknown_ids, malformed = [], [], 0
    for line in open(args.run):
        if not line.startswith("BENCH "):
            continue
        try:
            event = json.loads(line[6:])
            kind = event["event"]
        except (json.JSONDecodeError, KeyError):
            malformed += 1
            continue
        if kind == "loaded":
            print(f"model loaded in {event['seconds']:.1f} s, {event['cpu']:.1f} processor-seconds")
        elif kind == "result":
            if event.get("id") in made:
                rows.append(event)
            else:
                unknown_ids.append(event.get("id"))
    print(f"normalisation: {normalisation_rules()}")
    normalise_all([t for r in rows for t in (made[r["id"]]["spoken"], made[r["id"]]["written"],
                                            made[r["id"]].get("devanagari") or "", r.get("text", ""),
                                            " ".join(e["text"] for e in r["events"] if e["kind"] == "asr"))])
    scored = []
    for r in rows:
        c = made[r["id"]]
        heard = [e for e in r["events"] if e["kind"] == "asr"]
        tidied = [e for e in r["events"] if e["kind"] == "clean"]
        key_up = next(float(e["t"]) for e in r["events"] if e["kind"] == "keyup")
        early = [float(e["t1"]) for e in tidied if float(e["t1"]) <= key_up]
        raw_e, raw_n = errors([c["spoken"], c.get("devanagari")], " ".join(e["text"] for e in heard))
        out_e, out_n = errors([c["written"], c.get("devanagari")], r.get("text", ""))
        exact = errors([c["written"]], r.get("text", ""), words=exact_words)
        scored.append(dict(r=r, c=c, raw=(raw_e, raw_n), out=(out_e, out_n), exact=exact,
                           first_early=min(early) if early else None,
                           asr=sum(float(e["t1"]) - float(e["t0"]) for e in heard),
                           tidy=sum(float(e["t1"]) - float(e["t0"]) for e in tidied)))
    if not scored:
        details = []
        if unknown_ids:
            details.append(f"{len(unknown_ids)} result(s) with an id not in the corpus: {sorted(set(unknown_ids))[:10]}")
        if malformed:
            details.append(f"{malformed} malformed or unrecognized BENCH line(s)")
        reason = "; ".join(details) if details else "the run file had no BENCH result events"
        sys.exit(f"no recognized results scored in {args.run} ({reason})")
    if unknown_ids:
        print(f"\n{len(unknown_ids)} result(s) had an id not in the corpus: {sorted(set(unknown_ids))}")
    if malformed:
        print(f"{malformed} malformed or unrecognized BENCH line(s) were skipped")

    def wer_table(title, key, keep):
        groups = defaultdict(list)
        for s in scored:
            if keep(s): groups[key(s)].append(s)
        print(f"\n{title}\n\n| | clips | raw WER | final WER | final exact WER |\n|---|---|---|---|---|")
        for k in sorted(groups):
            g = groups[k]
            raw = sum(s["raw"][0] for s in g) / max(1, sum(s["raw"][1] for s in g))
            out = sum(s["out"][0] for s in g) / max(1, sum(s["out"][1] for s in g))
            exact = sum(s["exact"][0] for s in g) / max(1, sum(s["exact"][1] for s in g))
            print(f"| {k} | {len(g)} | {100 * raw:.1f}% | {100 * out:.1f}% | {100 * exact:.1f}% |")

    for cleaner in sorted({s["r"]["cleaner"] for s in scored}):
        for mode in sorted({s["r"]["mode"] for s in scored}):
            mine = lambda s, cl=cleaner, m=mode: s["r"]["cleaner"] == cl and s["r"]["mode"] == m
            if not any(mine(s) for s in scored): continue
            print(f"\n## cleaner {cleaner}, mode {mode}")
            wer_table("Word error rate by category, clean audio", lambda s: s["c"]["category"],
                      lambda s: mine(s) and s["c"]["variant"] == "clean")
            wer_table("Word error rate by language and voice, clean audio", lambda s: f"{s['c']['language']}, {s['c']['voice']}",
                      lambda s: mine(s) and s["c"]["variant"] == "clean")
            wer_table("Word error rate by audio variant, over the variant bases", lambda s: s["c"]["variant"],
                      lambda s: mine(s) and (s["c"]["id"] in VARIANT_BASES or s["c"]["id"].rsplit("-", 1)[0] in VARIANT_BASES))
            groups = defaultdict(list)
            for s in scored:
                if mine(s) and s["c"]["variant"] == "clean":
                    cat = s["c"]["category"]
                    groups[cat if cat == "reply" or cat.startswith("dur") else
                           "other, Hindi" if s["c"]["language"] != "english" else "other, English"].append(s)
            print("\nCost, clean audio\n\n| | clips | speech s | wait p50 | wait p95 | first early piece p50 | "
                  "recognising p50 | tidying p50 | processor s per speech s | peak footprint MB |")
            print("|---|---|---|---|---|---|---|---|---|---|")
            for k in sorted(groups):
                g = groups[k]
                waits = [s["r"]["wait"] for s in g]
                early = [s["first_early"] for s in g if s["first_early"] is not None]
                cells = [len(g), f"{statistics.mean(s['r']['audio'] for s in g):.1f}", f"{percentile(waits, 50):.2f}",
                         f"{percentile(waits, 95):.2f}", f"{percentile(early, 50):.1f}" if early else "—",
                         f"{percentile([s['asr'] for s in g], 50):.2f}", f"{percentile([s['tidy'] for s in g], 50):.2f}",
                         f"{sum(s['r']['cpu'] for s in g) / sum(s['r']['audio'] for s in g):.3f}",
                         f"{max(s['r']['peakMB'] for s in g):.0f}"]
                print(f"| {k} | " + " | ".join(str(x) for x in cells) + " |")
            devvocab_pairs(scored, mine)
    failed = [(s["r"]["id"], s["r"]["failed"]) for s in scored if s["r"].get("failed")]
    print(f"\nfailed: {failed or 'none'}")
    unstable(scored)


def term_heard(term, text):
    """Whether the term's normalised words appear, in order and adjacent, in the text."""
    t, h = normalise(term), normalise(text)
    return any(h[i:i + len(t)] == t for i in range(len(h) - len(t) + 1))


def devvocab_pairs(scored, keep):
    """Developer vocabulary bare against after a lead-in: the term heard, and its clip's WER, per category."""
    groups = defaultdict(lambda: defaultdict(list))
    for s in scored:
        if keep(s) and s["c"]["variant"] == "clean" and s["c"].get("context"):
            groups[s["c"]["category"]][s["c"]["context"]].append(s)
    if not groups:
        return
    print("\nDeveloper vocabulary, bare against after a lead-in (paired)\n\n"
          "| | pairs | bare raw WER | context raw WER | bare term heard | context term heard |\n|---|---|---|---|---|---|")
    for k in sorted(groups):
        cells = [min(len(groups[k]["bare"]), len(groups[k]["context"]))]
        for context in ("bare", "context"):
            g = groups[k][context]
            cells.append(f"{100 * sum(s['raw'][0] for s in g) / max(1, sum(s['raw'][1] for s in g)):.1f}%")
        for context in ("bare", "context"):
            g = groups[k][context]
            heard = sum(term_heard(s["c"]["term"], " ".join(e["text"] for e in s["r"]["events"] if e["kind"] == "asr"))
                        for s in g)
            cells.append(f"{heard}/{len(g)}")
        print(f"| {k} | " + " | ".join(str(x) for x in cells) + " |")


def unstable(scored):
    """Clips run more than once that did not give the same text every run. See Docs/speech-engines.md."""
    outputs = defaultdict(Counter)
    for s in scored:
        r = s["r"]
        outputs[(r["id"], r["cleaner"], r["mode"])][r.get("text", f"failed: {r.get('failed')}")] += 1
    varied = {k: v for k, v in outputs.items() if len(v) > 1}
    print(f"\nrepeated clips that answered differently on the same audio: {len(varied) or 'none'}")
    for (cid, cleaner, mode), counted in sorted(varied.items()):
        print(f"\n  {cid}, cleaner {cleaner}, mode {mode}, {sum(counted.values())} runs")
        for text, n in counted.most_common():
            print(f"    {n:>4} \u00d7 {text!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT, help="where the corpus lives (default .build/bench)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("corpus", help="synthesise the corpus with say")
    j = sub.add_parser("jobs", help="print a jobs file for uttrflow-dev bench")
    j.add_argument("--mode", default="fast", choices=["fast", "rt"])
    j.add_argument("--cleaners", default="shipping", help="comma-separated: shipping, rules")
    j.add_argument("--categories", default="", help="comma-separated categories, all when empty")
    j.add_argument("--clean-only", action="store_true", help="leave out the noise and gain variants")
    j.add_argument("--repeat", type=int, default=1)
    s = sub.add_parser("score", help="score the output of uttrflow-dev bench")
    s.add_argument("run")
    args = parser.parse_args()
    {"corpus": corpus, "jobs": jobs, "score": score}[args.command](args)


if __name__ == "__main__":
    main()
