# CLAUDE.md

Guidance for coding agents working in this repository.

- Three independent tools: `macbindings/` (Swift menu-bar app), `clipboard-typer/`
  (Swift daemon), `kitty-tmux-prefix/` (shell). Each has its own README; keep it
  current when behavior changes.
- Run `./tests/run.sh` before committing. Swift checks only run on macOS; on
  other systems rely on CI's macOS job.
- Keep routing and geometry logic in `macbindings/Sources/Bindings.swift` free of
  AppKit side effects, and cover new behavior in `Tests/RoutingTests.swift`.
- Installers archive instead of deleting. Don't add `rm` to install paths.
- Never log keystrokes or clipboard contents, and never automate privacy approvals.
- No personal data: `tests/run.sh` fails on home-directory paths, IP addresses,
  email addresses and issue-tracker ids anywhere in the tree.
