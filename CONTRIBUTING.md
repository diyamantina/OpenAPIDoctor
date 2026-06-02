# Contributing to OpenAPIDoctor

Thanks for your interest in OpenAPIDoctor. This guide covers how to set up, the
conventions the project follows, and how to land a change.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## What this is

OpenAPIDoctor is a Swift library plus a CLI (`openapi-doctor`) that diagnoses and
repairs OpenAPI 3.0 and 3.1 specs through OpenAPIKit. It is a standalone Swift
package: `Package.swift` lives at the repo root. The library and CLI depend only
on cross-platform packages (OpenAPIKit, Yams, Stitcher) and Foundation, so the
project builds and tests on both macOS and Linux.

## Getting started

You need a recent Swift toolchain (Swift 5.9 or newer). From the repo root:

```sh
swift build
swift test
swift run openapi-doctor --help
```

## Conventions

- One non-private type per file; the file is named for that type. Types live
  under the `OpenAPIDoctor` namespace mirrored by the folder layout.
- Dependencies are injected through initialisers. No force-unwrapping, no
  `try!`, no `as!` in shipping code (`Sources/`). Tests may use them.
- Formatting and linting are mechanical and enforced. Before committing:

  ```sh
  swiftformat . --config .swiftformat
  swiftlint lint --config .swiftlint.yml --strict
  ```

- Tests use the Swift Testing framework (`@Test`, `@Suite`, `#expect`) and assert
  behaviour against real fixture specs, not implementation details.

Read the surrounding code before writing new code and match what is already
there. Consistency with existing code outranks personal preference.

## Commits

Commit messages follow Conventional Commits: `<type>(<scope>): summary`, lowercase
type, imperative mood, no trailing period, first line under 72 characters. Types:
`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`.

Do not include tool attribution of any kind, and do not use em dashes in commit
messages, code, or documentation. The `scripts/check-style.sh` gate enforces both
in CI.

## Branches

Branch from the current tip of `main`:

```sh
git fetch origin main && git checkout -b feat/<topic> origin/main
```

Naming: `fix/<issue>-<topic>`, `feat/<topic>`, `chore/<topic>`, `docs/<topic>`,
`refactor/<topic>`.

## Pull requests

- One focused change per PR. If the diff spans two unrelated concerns, split it.
- Add a `CHANGELOG.md` entry under `Unreleased` for any change that touches
  shipping source. Docs, tests, and config-only changes do not need an entry.
- Run the full local gate and confirm it passes before opening the PR:

  ```sh
  bash scripts/check-style.sh
  bash scripts/check-namespacing.sh
  swiftformat . --config .swiftformat --lint
  swiftlint lint --config .swiftlint.yml --strict
  swift build
  swift test
  ```

  The same gates run in GitHub CI (`.github/workflows/`) on both macOS and Linux
  as the backstop.
- Do a self-review pass on your own diff and fix what a reviewer would flag.

## Issues

For bugs, file an issue first using the bug form, then branch with the issue
number in the name. The issue is the durable record of symptom, reproduction, and
acceptance criteria. For features, an issue is recommended when the scope is
non-trivial.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
