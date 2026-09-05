import UttrflowPredict

extension FixtureCatalogue {
    /// Shell lines whose arguments the machine can vouch for or deny: paths from the working directory, branches, targets and scripts, beside a stale scrollback and names that are not there. See `Docs/predict-agent.md`, A5.
    static let cwd: [Scenario] = [grounded, absent]

    /// What the substitute machine holds for a terminal sitting in `/Users/me/projects/api`.
    private static let machine: [EnvironmentKind: [String]] = [
        .directory: ["Sources", "Tests", "Scripts", "docs", "node_modules"],
        .file: [
            "Sources", "Tests", "Scripts", "docs", "node_modules", "Package.swift", "Makefile",
            "package.json",
            "README.md", ".env", ".gitignore",
        ],
        .directories(under: "Sources"): ["Login", "Billing", "Shared"],
        .entries(under: "Sources"): ["Login", "Billing", "Shared"],
        .entries(under: "Sources/Login"): ["Session.swift", "Token.swift"],
        .directories(under: "Sources/Login"): [],
        .entries(under: "docs"): ["README.md", "deploy.md"],
        .directories(under: "docs"): [],
        .entries(under: "Tests"): ["LoginTests"],
        .entries(under: "Sources/Nowhere"): [],
        .directories(under: "Sources/Nowhere"): [],
        .entries(under: "feat"): [],
        .entries(under: "fix"): [],
        .directories(under: "projects"): [],
        .entries(under: "projects"): [],
        .directories(under: "projects/x-growth"): [],
        .branch: ["main", "fix/login-timeout", "release"],
        .subcommand(of: "make"): ["verify", "build", "test", "lint", "format"],
        .subcommand(of: "npm run"): ["dev", "build", "test", "lint"],
        .subcommand(of: "git"): [
            "add", "branch", "checkout", "commit", "diff", "fetch", "log", "merge", "pull", "push", "rebase",
            "stash", "status", "switch",
        ],
        .gitAlias: [],
        .executable: ["git", "make", "npm", "vim", "cat", "ls", "cd", "docker", "kubectl", "swift", "code"],
        .alias: [],
    ]

    /// A stale scrollback: the previous shell sat in Desktop, and its `cd` lines name what is not under this directory.
    private static let situation = terminal(
        directory: "/Users/me/projects/api", title: "api — zsh",
        scrollback: """
            $ cd projects/x-growth/backend
            $ git status
            On branch fix/login-timeout
            nothing to commit, working tree clean
            $ ls
            Sources Tests Scripts docs Package.swift Makefile package.json README.md
            """,
        recent: ["git status", "make verify", "cd Sources/Login", "npm run dev", "git checkout main"])

    /// Lines every argument of which the machine holds, cut where the model has to pick the right one.
    private static let grounded = Scenario(
        category: "terminal", name: "cwd", situation: situation,
        cuts: .command, determinacy: .command, band: 1...48, machine: machine,
        lines: [
            "cd Sources/Login", "cd Scripts", "cd Sources/Billing", "vim Sources/Login/Session.swift",
            "cat docs/deploy.md", "ls Tests", "git checkout fix/login-timeout", "git switch release",
            "make verify", "make lint", "npm run dev", "npm run build", "vim .env", "cat Package.swift",
            "git add Sources/Login/Token.swift",
        ])

    /// Lines naming what is not here, cut at the word the machine denies, where the right answer is nothing.
    private static let absent = Scenario(
        category: "terminal", name: "cwd-absent", situation: situation,
        cuts: [.whole], determinacy: .nothing, band: 1...48, machine: machine,
        lines: [
            "cd projects/x-growth/", "vim .env.vim", "cd Sources/Nowhere/", "make venv", "npm run observe",
            "git checkout feat/", "cat docs/missing.md",
        ])
}
