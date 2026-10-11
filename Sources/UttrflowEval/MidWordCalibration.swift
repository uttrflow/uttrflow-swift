/// Command-line prefixes cut inside their last word, each with the lines a floor must keep and the lines it must refuse. See `Docs/predict-midword.md`.
package enum MidWordCalibration {
    /// One prefix with whole lines that continue it sensibly and whole lines that only look as if they do.
    package struct Probe: Sendable, Equatable {
        package let typed: String
        package let sensible: [String]
        package let nonsense: [String]

        package init(_ typed: String, sensible: [String], nonsense: [String]) {
            self.typed = typed
            self.sensible = sensible
            self.nonsense = nonsense
        }

        /// The tool the prefix is for, which is its first word.
        package var tool: String {
            String(typed.split(separator: " ", omittingEmptySubsequences: true).first ?? "")
        }

        /// Whether every line begins with the prefix and the prefix stops inside a word of it.
        package var isCutMidWord: Bool {
            guard let last = typed.last, !last.isWhitespace else { return false }
            return (sensible + nonsense).allSatisfy { line in
                guard line.hasPrefix(typed) else { return false }
                let rest = line.dropFirst(typed.count)
                return rest.first.map { !$0.isWhitespace } ?? false
            }
        }
    }

    /// The model's score for one line after one prefix, nil when it had none.
    package struct Scored: Sendable, Equatable {
        package let typed: String
        package let line: String
        package let isSensible: Bool
        package let score: Double?

        package init(typed: String, line: String, isSensible: Bool, score: Double?) {
            self.typed = typed
            self.line = line
            self.isSensible = isSensible
            self.score = score
        }
    }

    /// What one floor does to a scored set.
    package struct Tally: Sendable, Equatable {
        package let floor: Double
        package let sensibleKept: Int
        package let sensibleTotal: Int
        package let nonsensePassed: Int
        package let nonsenseTotal: Int
        package let unscored: Int
    }

    /// Counts the lines that clear `floor`, a non-finite score never clearing it and a line with no score counted apart.
    package static func tally(_ scored: [Scored], floor: Double) -> Tally {
        let measured = scored.filter { $0.score != nil }
        let clears = { (line: Scored) in
            guard let score = line.score else { return false }
            return score.isFinite && score >= floor
        }
        let sensible = measured.filter(\.isSensible)
        let nonsense = measured.filter { !$0.isSensible }
        return Tally(
            floor: floor, sensibleKept: sensible.count(where: clears), sensibleTotal: sensible.count,
            nonsensePassed: nonsense.count(where: clears), nonsenseTotal: nonsense.count,
            unscored: scored.count - measured.count)
    }

    /// A Markdown row per floor in `floors`, for reading where the trade between kept and passed turns.
    package static func markdown(_ scored: [Scored], floors: [Double]) -> String {
        var lines = [
            "| Floor | Sensible kept | Nonsense passed |",
            "|---|--:|--:|",
        ]
        for floor in floors {
            let result = tally(scored, floor: floor)
            lines.append(
                "| \(floor) | \(result.sensibleKept) of \(result.sensibleTotal) | "
                    + "\(result.nonsensePassed) of \(result.nonsenseTotal) |")
        }
        let unscored = scored.count(where: { $0.score == nil })
        if unscored > 0 { lines.append("\n\(unscored) lines had no score and are left out of every row.") }
        return lines.joined(separator: "\n")
    }

    /// Every line of every probe with its label, ready to be scored.
    package static func lines(of probes: [Probe] = all) -> [Scored] {
        probes.flatMap { probe in
            probe.sensible.map { Scored(typed: probe.typed, line: $0, isSensible: true, score: nil) }
                + probe.nonsense.map { Scored(typed: probe.typed, line: $0, isSensible: false, score: nil) }
        }
    }

    /// Invented, realistic prefixes across several tools and argument shapes, with no real paths, hosts or history.
    package static let all: [Probe] = [
        Probe("gi", sensible: ["git status", "git commit -m 'update'"], nonsense: ["gizmo --frobnicate"]),
        Probe("git sta", sensible: ["git status", "git stash pop"], nonsense: ["git stabilize --deep"]),
        Probe(
            "git che", sensible: ["git checkout main", "git cherry-pick abc1234"],
            nonsense: ["git chewbacca main"]),
        Probe(
            "git pu", sensible: ["git pull --rebase", "git push origin main"],
            nonsense: ["git pumpkin origin main"]),
        Probe(
            "git log --one", sensible: ["git log --oneline", "git log --oneline -10"],
            nonsense: ["git log --oneirics"]),
        Probe("do", sensible: ["docker ps", "docker compose up -d"], nonsense: ["dozzle --quantum"]),
        Probe(
            "docker ru", sensible: ["docker run --rm -it ubuntu bash", "docker run -p 8080:80 nginx"],
            nonsense: ["docker rumble --fast"]),
        Probe(
            "docker comp", sensible: ["docker compose up -d", "docker compose down"],
            nonsense: ["docker compost --turn"]),
        Probe(
            "docker ima", sensible: ["docker images", "docker image prune"],
            nonsense: ["docker imagine --sparkle"]),
        Probe(
            "kub", sensible: ["kubectl get pods", "kubectl apply -f deploy.yaml"],
            nonsense: ["kubrick --widescreen"]),
        Probe(
            "kubectl get po", sensible: ["kubectl get pods", "kubectl get pods -n staging"],
            nonsense: ["kubectl get pomegranates"]),
        Probe(
            "kubectl descr", sensible: ["kubectl describe pod web-0", "kubectl describe node worker-1"],
            nonsense: ["kubectl descramble pod web-0"]),
        Probe(
            "kubectl rol",
            sensible: ["kubectl rollout status deploy/web", "kubectl rollout restart deploy/web"],
            nonsense: ["kubectl rolodex status"]),
        Probe(
            "swift b", sensible: ["swift build", "swift build -c release"],
            nonsense: ["swift bamboozle --all"]),
        Probe(
            "swift te", sensible: ["swift test", "swift test --filter ParserTests"],
            nonsense: ["swift teleport --now"]),
        Probe(
            "swift pack", sensible: ["swift package resolve", "swift package clean"],
            nonsense: ["swift packrat --hoard"]),
        Probe("np", sensible: ["npm install", "npm run build"], nonsense: ["npq --zorp"]),
        Probe("npm ru", sensible: ["npm run build", "npm run test"], nonsense: ["npm rumble --max"]),
        Probe(
            "npm inst", sensible: ["npm install", "npm install --save-dev typescript"],
            nonsense: ["npm instigate --loud"]),
        Probe(
            "npx ts", sensible: ["npx tsc --noEmit", "npx tsx script.ts"], nonsense: ["npx tsunami --wave"]),
        Probe("bre", sensible: ["brew install wget", "brew update"], nonsense: ["breakfast --toast"]),
        Probe(
            "brew upg", sensible: ["brew upgrade", "brew upgrade --greedy"],
            nonsense: ["brew upgleam --shine"]),
        Probe("carg", sensible: ["cargo build --release", "cargo test"], nonsense: ["cargoyle --stone"]),
        Probe(
            "cargo ch", sensible: ["cargo check", "cargo check --all-targets"],
            nonsense: ["cargo chowder --hot"]),
        Probe(
            "cargo cl", sensible: ["cargo clippy", "cargo clean"], nonsense: ["cargo clobber --everything"]),
        Probe(
            "pyt", sensible: ["python3 -m venv .venv", "python3 main.py"], nonsense: ["pythonic --enlighten"]),
        Probe(
            "pip ins", sensible: ["pip install requests", "pip install -r requirements.txt"],
            nonsense: ["pip insulate --warm"]),
        Probe(
            "python3 -m ht", sensible: ["python3 -m http.server 8000", "python3 -m http.server"],
            nonsense: ["python3 -m httpotato"]),
        Probe("mak", sensible: ["make build", "make test"], nonsense: ["makeover --glam"]),
        Probe("make ver", sensible: ["make verify", "make verify -j4"], nonsense: ["make verbena --petals"]),
        Probe(
            "cur", sensible: ["curl -s example.com", "curl -I example.com"],
            nonsense: ["curious --george"]),
        Probe(
            "curl -X PO",
            sensible: [
                "curl -X POST example.com/api", "curl -X POST -d @body.json example.com/api",
            ], nonsense: ["curl -X POTATO example.com/api"]),
        Probe(
            "gre", sensible: ["grep -rn TODO .", "grep -i error app.log"], nonsense: ["greenhouse --grow"]),
        Probe(
            "grep --inc", sensible: ["grep --include=*.swift -rn TODO .", "grep --include=*.md -rn TODO ."],
            nonsense: ["grep --incense=lavender -rn TODO ."]),
        Probe(
            "ta", sensible: ["tar -xzf archive.tar.gz", "tail -f app.log"], nonsense: ["tapioca --pearls"]),
        Probe(
            "tar -xz", sensible: ["tar -xzf archive.tar.gz", "tar -xzvf backup.tgz"],
            nonsense: ["tar -xzebra stripes"]),
        Probe(
            "systemctl sta", sensible: ["systemctl status nginx", "systemctl start nginx"],
            nonsense: ["systemctl stapler nginx"]),
        Probe(
            "terraform ini", sensible: ["terraform init", "terraform init -upgrade"],
            nonsense: ["terraform inigo montoya"]),
        Probe(
            "terraform pl", sensible: ["terraform plan", "terraform plan -out=tfplan"],
            nonsense: ["terraform plumb --pipes"]),
        Probe(
            "go te", sensible: ["go test ./...", "go test -run TestParse ./pkg"],
            nonsense: ["go tectonic --shift"]),
        Probe("go mod ti", sensible: ["go mod tidy", "go mod tidy -v"], nonsense: ["go mod tiara --crown"]),
        Probe(
            "ffm", sensible: ["ffmpeg -i input.mov output.mp4", "ffmpeg -i clip.mp4 -vn audio.mp3"],
            nonsense: ["ffmpegger --burger"]),
        Probe(
            "rsy", sensible: ["rsync -av src/ backup/", "rsync -avz --progress src/ backup/"],
            nonsense: ["rsyncopate --jazz"]),
        Probe("chm", sensible: ["chmod +x deploy.sh", "chmod 644 notes.txt"], nonsense: ["chmunk --crunch"]),
        Probe(
            "ssh-k", sensible: ["ssh-keygen -t ed25519", "ssh-keyscan example.com"],
            nonsense: ["ssh-kangaroo --hop"]),
        Probe(
            "tmux att", sensible: ["tmux attach -t work", "tmux attach"], nonsense: ["tmux attic -t work"]),
        Probe(
            "jq .it", sensible: ["jq .items[] data.json", "jq .items data.json"],
            nonsense: ["jq .itchy scratch data.json"]),
    ]
}
