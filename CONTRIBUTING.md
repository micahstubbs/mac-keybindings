# Contributing

Issues and pull requests are welcome.

## Ground rules

- Keep each tool small and dependency-free: Swift from the macOS SDK, Bash, and
  Python 3's standard library in installers.
- Installers must never delete a user's files. Move previous versions into an
  archive directory, as the existing installers do.
- Never log typed text or clipboard contents.
- Pass through every event you don't fully match. If you swallow a press,
  swallow its paired release too.
- Don't automate macOS privacy approvals or touch the TCC database.

## Before sending a change

```bash
./tests/run.sh
```

On macOS this also compiles and runs the Swift tests. For MacBindings behavior
changes, add a case to `macbindings/Tests/RoutingTests.swift`; the routing and
geometry code in `Bindings.swift` is deliberately free of AppKit side effects so
it can be unit-tested. If you change how windows are moved, also run
`./macbindings/macbindings.sh live-test` against an installed build and say in
the pull request which macOS version and hardware you used.

Shell scripts use `set -euo pipefail` and should pass ShellCheck, which CI runs.
