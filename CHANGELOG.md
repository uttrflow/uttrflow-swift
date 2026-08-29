# Changelog

Notable changes to Uttrflow. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org).

Each released version is a git tag and a build at
[uttrflow/releases](https://github.com/uttrflow/releases).

## [Unreleased]

### Added
- Continuous integration on every pull request, and a tag-driven release workflow.
- `CONTRIBUTING.md`, `RELEASING.md`, `SECURITY.md` and a code of conduct.

## [0.2.2] — 2026-08-29

First public release of the source. The app itself has been shipping since 0.1.0; this is
where its code became readable.

### Added
- Work on this Mac without an Uttrflow account, using the name macOS already knows you by.
  Sign-in was the one screen that could not work offline; it now has a way through that
  needs nothing.
- Automatic updates through Sparkle, checked against a key compiled into each build.
- A Position Monitoring view, and version reporting at the foot of the sidebar.

### Fixed
- The sidebar no longer claims a session nobody has.
- One retention window now governs both copies of a transcript, rather than two that could
  disagree.

[Unreleased]: https://github.com/uttrflow/uttrflow-swift/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.2.2
