# Counting network requests

`NetworkActivityLedger` in `UttrflowCore` aggregates counts, while each URL session transport owns
a thin task observer in its module. Swift `internal` types cannot be shared across package targets;
a common observer would need a new public API and widen the supported surface. Request bodies, URLs
and responses are never stored. A failed task is counted at task creation, and each Hub file and
Sentry envelope gets its own task count.

The account transport records its `BackendRequest` purpose immediately before starting the task.
Speech weight downloads do the same at their downloader boundary. Sparkle does not expose its
feed session, so `UpdateController` counts appcast success and failure callbacks once per update
cycle and counts the archive in its pre-download callback.

`offline_audit.sh` checks each transport's binding and observer callbacks individually. Its audit
tests remove each binding to prove that a transport can no longer silently stop counting.
