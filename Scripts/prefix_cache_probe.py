#!/usr/bin/env python3
# Tests whether a decoder prefix cache from one clip reproduces another clip's decode. See Docs/speech-vocabulary-prompt.md.
import argparse, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MODEL = os.path.expanduser(
    "~/Library/Application Support/Uttrflow/Models/openai_whisper-large-v3-v20240930_turbo_632MB")
VOICES = ["Samantha", "Daniel", "Rishi"]
SENTENCES = [
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
]
# Invented vocabulary entries, spaced as the app writes the prompt.
VOCABULARY = (
    "Zentrova Kalpix Merrowind Drovatek Quillstone Vantaro Brisklet Ombrifex Talverin Pellucid Scrimshaw "
    "Fennarow Glimmerdyne Hollowmere Isotrine Jorvik Kestrelon Lumivane Marrowgate Nimbrel Orthanex Prismora "
    "Quorvane Rillgate Sablethorn Tindrel Umbraval Veltrix Wyndhollow Xantelle Yarrowby Zephyrine Ashcombe "
    "Brackenridge Corvantis Duskwater Emberlyn Falconridge Galewright Harrowfield Ironvale Juniperton "
    "Kingsmere Larkspur Mistralon Northcairn Oakhallow Pinecrest Quarrymoor Ravenholt Silverbrook Thornbury")


def bytes_to_unicode():
    bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return dict(zip(bs, map(chr, cs)))


class Tokenizer:
    """Byte-level BPE over the model's own tokenizer.json, for ASCII text only."""

    def __init__(self, path):
        model = json.load(open(path))["model"]
        self.vocab = model["vocab"]
        self.inverse = {v: k for k, v in self.vocab.items()}
        merges = [tuple(m.split(" ")) if isinstance(m, str) else tuple(m) for m in model["merges"]]
        self.ranks = {m: i for i, m in enumerate(merges)}
        self.byte_map = bytes_to_unicode()
        self.unbyte = {v: k for k, v in self.byte_map.items()}

    def piece(self, word):
        parts = list(word)
        while len(parts) > 1:
            pairs = [(self.ranks.get((a, b), 1 << 30), i) for i, (a, b) in enumerate(zip(parts, parts[1:]))]
            rank, i = min(pairs)
            if rank == 1 << 30:
                break
            parts[i:i + 2] = [parts[i] + parts[i + 1]]
        return [self.vocab[p] for p in parts]

    def encode(self, text):
        out = []
        for word in re.findall(r"'s|'t|'re|'ve|'m|'ll|'d| ?[A-Za-z]+| ?[0-9]+| ?[^\sA-Za-z0-9]+|\s+", text):
            out += self.piece("".join(self.byte_map[b] for b in word.encode()))
        return out

    def decode(self, tokens):
        text = "".join(self.inverse.get(t, "") for t in tokens if t < 50257)
        return bytes(self.unbyte[c] for c in text).decode(errors="replace")


def special(path, name):
    return next(a["id"] for a in json.load(open(path))["added_tokens"] if a["content"] == name)


def synthesize(out):
    paths = []
    for i, sentence in enumerate(SENTENCES):
        path = os.path.join(out, f"clip{i:02d}.wav")
        if not os.path.exists(path):
            subprocess.run(["say", "-v", VOICES[i % len(VOICES)], "-o", path, "--file-format=WAVE",
                            "--data-format=LEI16@16000", sentence], check=True)
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--out", default=os.path.join(ROOT, ".build", "prefix-cache-probe"))
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    tokenizer_path = os.path.join(args.model, "tokenizer.json")
    tok = Tokenizer(tokenizer_path)
    words = tok.encode(" " + VOCABULARY)
    previous = special(tokenizer_path, "<|startofprev|>")
    tail = [special(tokenizer_path, n) for n in
            ("<|startoftranscript|>", "<|en|>", "<|transcribe|>", "<|notimestamps|>")]
    job = dict(clips=synthesize(args.out), tail=tail, end=special(tokenizer_path, "<|endoftext|>"), max_new_tokens=96,
               prompts={"prompt000": [], "prompt020": [previous] + words[:20], "prompt111": [previous] + words[:111]})
    job_path, result_path = os.path.join(args.out, "job.json"), os.path.join(args.out, "result.json")
    json.dump(job, open(job_path, "w"))
    binary = os.path.join(args.out, "prefix_cache_probe")
    subprocess.run(["swiftc", "-O", "-o", binary, os.path.join(ROOT, "Scripts", "prefix_cache_probe.swift")], check=True)
    subprocess.run([binary, args.model, job_path, result_path], check=True)
    result = json.load(open(result_path))
    print(f"seconds {result['seconds']:.0f}")
    print("| Prompt | Transplanted | Max logit diff | Top-1 same | Transcripts same | Largest key/value diff by layer |")
    print("|---|---|---|---|---|---|")
    for name in ("prompt000", "prompt020", "prompt111"):
        rows = result[name]
        layers = [max(r["layer_diff"][l] for r in rows) for l in range(4)]
        for variant in ("repeat", "whole_prefix", "prompt_only", "library_prefill"):
            if variant not in rows[0]:
                continue
            cells = [r[variant] for r in rows]
            shown = layers if variant == "whole_prefix" else (
                [max(r["library_layer_diff"][l] for r in rows) for l in range(4)] if variant == "library_prefill" else None)
            print(f"| {len(job['prompts'][name]) and len(job['prompts'][name]) - 1} | {variant} | "
                  f"{max(c['max_logit_diff'] for c in cells):.2f} | {sum(c['top1_same'] for c in cells)}/{len(cells)} | "
                  f"{sum(c['transcript_same'] for c in cells)}/{len(cells)} | "
                  f"{' / '.join(f'{v:.2f}' for v in shown) if shown else ''} |")
    for name in ("prompt000", "prompt020", "prompt111"):
        for r in result[name]:
            for variant in ("whole_prefix", "prompt_only", "library_prefill"):
                if variant in r and not r[variant]["transcript_same"]:
                    print(f"{name} {os.path.basename(r['clip'])} {variant}: {tok.decode(r['reference'])!r} -> "
                          f"{tok.decode(r[variant]['tokens'])!r}")


if __name__ == "__main__":
    sys.exit(main())
