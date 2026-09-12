# Working in this repository

`AGENTS.md` at the root is the rulebook, and it is the same file for every assistant.
Read it before proposing a change.

The rule most easily broken by an assistant is the one under **"What must never reach a
tracked file"**: this repository is public, the working session that produces the work is
not, and named competitors, growth or business strategy, and session talk never cross
from one to the other — not into a file, a commit message, a pull request or an issue.

`python3 Scripts/disclosure_audit.py` enforces it, and runs in `make verify`, in the git
hooks and on every pull request.
