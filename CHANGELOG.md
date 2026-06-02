# Changelog

All notable changes to OpenAPIDoctor are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Synthesise a missing `operationId` and inject a default `servers` block during
  `--fix`.
- `--corpus` directory-validation mode and form-safety guard support.
- `.swiftformat` and `.swiftlint.yml` config plus `scripts/check-style.sh` and
  `scripts/check-namespacing.sh` mechanical gates.
- GitHub Actions CI on macOS and Linux (style, format, lint, build, test).

## [1.0.0]

### Added

- Real-world multi-file FinTech corpus and corpus stress test.
- CLI `--help` / `-h` and `--no-resolve-refs` flags, `--output` flag, per-round
  streaming, and `--all` dry-run iterator.

## [0.2.0]

### Added

- Repair module, OpenAPI 3.0 support, and the CLI `--fix` flag.
