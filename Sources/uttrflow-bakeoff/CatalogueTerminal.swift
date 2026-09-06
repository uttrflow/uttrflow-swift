import UttrflowPredict

extension FixtureCatalogue {
    /// Shell lines in four terminals, each with its own scrollback and the commands this person ran there.
    static let terminal: [Scenario] = [
        Scenario(
            category: "terminal", name: "git",
            situation: terminal(
                directory: "/Users/me/projects/api", title: "api — zsh",
                scrollback: """
                    $ git status
                    On branch fix/login-timeout
                    Changes not staged for commit:
                      modified:   Sources/Login/Session.swift
                    $ git diff --stat
                     Sources/Login/Session.swift | 12 ++++----
                     1 file changed, 8 insertions(+), 4 deletions(-)
                    """,
                recent: [
                    "git diff --stat", "git status", "git checkout -b fix/login-timeout", "git pull --rebase",
                    "git log --oneline -20", "git push origin main",
                ]),
            cuts: .command, determinacy: .command, band: 1...48,
            known: [
                "git commit --amend", "git cherry-pick", "git clone", "git reset --hard", "git restore .",
                "git remote -v", "git show", "git switch main", "git tag", "git blame", "git bisect",
            ],
            machine: api,
            lines: [
                "git status", "git checkout main", "git checkout -b fix/login-timeout",
                "git commit -m 'fix login timeout'", "git push origin main", "git pull --rebase",
                "git log --oneline -20", "git diff --stat", "git stash pop", "git rebase -i main",
                "git fetch --all --prune", "git branch -d fix/login-timeout", "git merge --no-ff release",
                "git add -A",
            ]),
        Scenario(
            category: "terminal", name: "containers",
            situation: terminal(
                directory: "/Users/me/projects/api", title: "api — docker",
                scrollback: """
                    $ docker ps --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}'
                    NAMES   IMAGE         STATUS
                    api     api:latest    Up 2 hours
                    db      postgres:16   Up 2 hours
                    $ kubectl config current-context
                    staging
                    """,
                recent: [
                    "kubectl config current-context", "docker ps", "docker compose up -d",
                    "docker logs -f api",
                    "kubectl get pods -n staging", "docker compose down",
                ]),
            cuts: .command, determinacy: .command, band: 1...48,
            known: [
                "docker run --rm -it", "docker pull", "docker push", "docker stop", "docker rm",
                "docker images",
                "docker inspect", "docker volume ls", "docker network ls", "kubectl delete pod",
                "kubectl port-forward", "kubectl exec -it", "kubectl top pods", "kubectl scale",
            ],
            machine: api,
            lines: [
                "docker compose up -d", "docker compose down", "docker ps -a", "docker build -t api:latest .",
                "docker logs -f api", "docker exec -it api sh", "docker image prune -f",
                "kubectl get pods -n staging", "kubectl describe pod api", "kubectl logs -f deploy/api",
                "kubectl apply -f k8s/deployment.yaml", "kubectl rollout restart deploy/api",
                "kubectl get svc",
                "kubectl config use-context staging",
            ]),
        Scenario(
            category: "terminal", name: "node",
            situation: terminal(
                directory: "/Users/me/projects/web", title: "web — zsh",
                scrollback: """
                    $ npm run build

                    > web@0.4.0 build
                    > vite build

                    ✓ 212 modules transformed.
                    dist/index.html   0.46 kB
                    ✓ built in 1.84s
                    """,
                recent: [
                    "npm run build", "npm run dev", "npm install", "npx tsc --noEmit", "npm test",
                    "git status",
                ]),
            cuts: .command, determinacy: .command, band: 1...48,
            known: [
                "npm ci", "npm start", "npm publish", "npm version patch", "npx vite", "npx playwright test",
                "yarn install", "yarn dev", "node --version", "node server.js",
            ],
            machine: web,
            lines: [
                "npm run build", "npm run dev", "npm install", "npm install --save-dev vitest", "npm test",
                "npx prettier --write .", "npx tsc --noEmit", "yarn add zod", "node scripts/seed.js",
                "npm run lint -- --fix", "npm outdated", "npx eslint src",
            ]),
        Scenario(
            category: "terminal", name: "shell",
            situation: terminal(
                directory: "/Users/me", title: "me — zsh",
                scrollback: """
                    $ ls
                    Desktop    Documents  Downloads  projects
                    $ cd projects
                    $ ls
                    api  web  notes
                    $ cd ..
                    """,
                recent: [
                    "cd ..", "ls", "cd projects", "make verify", "tail -f logs/app.log", "brew upgrade",
                    "python3 -m venv .venv",
                ]),
            cuts: .command, determinacy: .command, band: 1...48,
            known: [
                "ls -l", "ls -lh", "ls -a", "cd -", "cd ~", "grep -i", "grep -c", "ssh -i",
                "python3 -m pytest",
                "python3 -m http.server", "make clean", "make build", "make lint", "brew update", "brew list",
                "brew services", "cat README.md", "mkdir build", "tail -n 100", "chmod 644", "curl -I",
                "open -a",
            ],
            machine: home,
            lines: [
                Line("ls -la", determinacy: .any), "cd ~/projects/web", Line("cd ..", determinacy: .any),
                Line("grep -rn 'TODO' src", determinacy: .any), Line("ssh deploy@staging", determinacy: .any),
                "python3 -m venv .venv", Line("python3 manage.py migrate", determinacy: .any), "make verify",
                "make test", "brew install jq", "brew upgrade", "cat ~/.zshrc", "mkdir -p build/logs",
                "tail -f logs/app.log", "chmod +x scripts/deploy.sh",
                Line("curl -s localhost:3000/health", determinacy: .any), "open .",
            ]),
    ]

    /// The programs every terminal here has on its path.
    private static let programs = [
        "git", "docker", "kubectl", "npm", "npx", "yarn", "node", "python3", "make", "brew", "ls", "cd",
        "cat",
        "tail", "grep", "ssh", "mkdir", "chmod", "curl", "open", "vim", "code", "swift",
    ]

    /// What every git here accepts, as `git --list-cmds` would list it.
    private static let gitVerbs = [
        "add", "bisect", "blame", "branch", "checkout", "cherry-pick", "clone", "commit", "diff", "fetch",
        "log",
        "merge", "pull", "push", "rebase", "remote", "reset", "restore", "show", "stash", "status", "switch",
        "tag",
    ]

    /// The machine under `/Users/me/projects/api`: a Swift service with a Makefile, a manifest and a `k8s` folder.
    private static let api: [EnvironmentKind: [String]] = [
        .directory: ["Sources", "Tests", "Scripts", "k8s", "docs"],
        .file: [
            "Sources", "Tests", "Scripts", "k8s", "docs", "Package.swift", "Makefile", "README.md",
            "Dockerfile",
            "docker-compose.yml", ".env", ".gitignore",
        ],
        .entries(under: "Sources"): ["Login", "Billing"],
        .directories(under: "Sources"): ["Login", "Billing"],
        .entries(under: "Sources/Login"): ["Session.swift", "Token.swift"],
        .entries(under: "k8s"): ["deployment.yaml", "service.yaml"],
        .branch: ["main", "fix/login-timeout", "release", "origin/main", "origin/release", "v1.2.0"],
        .gitAlias: [],
        .subcommand(of: "git"): gitVerbs,
        .subcommand(of: "make"): ["verify", "build", "test", "lint", "clean"],
        .subcommand(of: "docker"): [
            "build", "compose", "exec", "image", "images", "inspect", "logs", "network", "ps", "pull", "push",
            "rm",
            "run", "stop", "volume",
        ],
        .subcommand(of: "kubectl"): [
            "apply", "config", "delete", "describe", "exec", "get", "logs", "port-forward", "rollout",
            "scale", "top",
        ],
        .executable: programs, .alias: [],
    ]

    /// The machine under `/Users/me/projects/web`: a Vite project with scripts in its manifest.
    private static let web: [EnvironmentKind: [String]] = [
        .directory: ["src", "dist", "scripts", "node_modules", "public"],
        .file: [
            "src", "dist", "scripts", "node_modules", "public", "package.json", "package-lock.json",
            "vite.config.ts", "tsconfig.json", "README.md", ".gitignore",
        ],
        .entries(under: "scripts"): ["seed.js", "build.sh"], .entries(under: "src"): ["main.ts", "App.tsx"],
        .branch: ["main"], .gitAlias: [],
        .subcommand(of: "git"): gitVerbs,
        .subcommand(of: "npm"): [
            "audit", "ci", "exec", "i", "init", "install", "ls", "outdated", "publish", "run", "start",
            "test",
            "uninstall", "update", "version",
        ],
        .subcommand(of: "npm run"): ["build", "dev", "lint", "preview", "test"],
        .subcommand(of: "yarn"): ["add", "build", "dev", "install", "remove", "run", "test"],
        .subcommand(of: "yarn run"): ["build", "dev", "lint", "preview", "test"],
        .executable: programs, .alias: [],
    ]

    /// The machine under `/Users/me`: a home directory with projects, logs and the scripts the lines touch.
    private static let home: [EnvironmentKind: [String]] = [
        .directory: ["Desktop", "Documents", "Downloads", "projects", "logs", "scripts", "build"],
        .file: [
            "Desktop", "Documents", "Downloads", "projects", "logs", "scripts", "build", "manage.py",
            "Makefile",
            ".zshrc", ".venv",
        ],
        .entries(under: "~"): [
            "Desktop", "Documents", "Downloads", "projects", "logs", "scripts", "build", "manage.py",
            "Makefile",
            ".zshrc", ".venv",
        ],
        .directories(under: "~"): [
            "Desktop", "Documents", "Downloads", "projects", "logs", "scripts", "build",
        ],
        .directories(under: "~/projects"): ["api", "web", "notes"],
        .entries(under: "~/projects"): ["api", "web", "notes"],
        .directories(under: "projects"): ["api", "web", "notes"],
        .entries(under: "projects"): ["api", "web", "notes"],
        .entries(under: "logs"): ["app.log", "error.log"],
        .entries(under: "scripts"): ["deploy.sh", "backup.sh"],
        .branch: [], .gitAlias: [],
        .subcommand(of: "git"): gitVerbs,
        .subcommand(of: "make"): ["verify", "test", "build", "lint", "clean"],
        .subcommand(of: "brew"): [
            "info", "install", "list", "search", "services", "uninstall", "update", "upgrade",
        ],
        .executable: programs, .alias: [],
    ]

    /// A terminal whose field holds the scrollback, with the commands this person ran in it.
    static func terminal(
        directory: String, title: String, scrollback: String, recent: [String]
    ) -> GenerationSituation {
        GenerationSituation(
            application: "Terminal", field: "AXTextArea", document: directory, preceding: scrollback,
            windowTitle: title, recentLines: recent)
    }
}
