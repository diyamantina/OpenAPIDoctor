# Changelog

All notable changes to OpenAPIDoctor are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-06-23

### Changed

- Require PureYAML 0.1.4 and Stitcher 2.0.1, which bound parser nesting depth so
  a pathologically nested spec fails with a diagnostic instead of crashing the
  process.

## [1.2.0] - 2026-06-23

### Changed

- Replace the Yams dependency with the pure-Swift
  [PureYAML](https://github.com/mihaelamj/PureYAML) (0.1.3) for all YAML parsing,
  decoding, and emitting, and move to
  [Stitcher](https://github.com/mihaelamj/Stitcher) 2.0.0. The validator,
  repairer, and degenerate-spec scanner now build on PureYAML's ordered value
  tree. This removes the libYaml C dependency from the whole chain, so
  OpenAPIDoctor compiles for WebAssembly (`wasm32-wasip1`). Public API and
  diagnostics are unchanged.

## [1.1.0] - 2026-06-02

### Added

- Synthesise a missing `operationId` and inject a default `servers` block during
  `--fix`. New public API: `DiagnosisKind.missingServers` and
  `.missingOperationId`, `RepairRoundKind.injectServers` and
  `.synthesizeOperationId`, the corresponding `RepairRound` fields, and the
  `OpenAPIDoctor.Synthesis` namespace (`Scanner`, `MissingOperationId`,
  `ScanResult`). Additive and backward-compatible.

### Changed

- Adopted mechanical formatting and linting gates: `.swiftformat` and
  `.swiftlint.yml`, plus `scripts/check-style.sh` and `scripts/check-namespacing.sh`.
- Added GitHub Actions CI on macOS and Linux (style, format, lint, build, test)
  and the matching README badges.
- Added community health files: Code of Conduct, Security policy, Support,
  Contributing, issue forms, and a pull-request template.

## [1.0.0]

### Added

- Real-world multi-file FinTech corpus and corpus stress test.
- `--corpus` directory-validation mode and form-safety guard support.
- CLI `--help` / `-h` and `--no-resolve-refs` flags, `--output` flag, per-round
  streaming, and `--all` dry-run iterator.

## [0.2.0]

### Added

- Repair module, OpenAPI 3.0 support, and the CLI `--fix` flag.
