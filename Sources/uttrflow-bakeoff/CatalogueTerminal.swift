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
            lines: [
                Line("ls -la", determinacy: .any), "cd ~/projects/web", Line("cd ..", determinacy: .any),
                Line("grep -rn 'TODO' src", determinacy: .any), Line("ssh deploy@staging", determinacy: .any),
                "python3 -m venv .venv", Line("python3 manage.py migrate", determinacy: .any), "make verify",
                "make test", "brew install jq", "brew upgrade", "cat ~/.zshrc", "mkdir -p build/logs",
                "tail -f logs/app.log", "chmod +x scripts/deploy.sh",
                Line("curl -s localhost:3000/health", determinacy: .any), "open .",
            ]),
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
