# OpenAPIDoctor

[![Style and namespacing](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/style.yml/badge.svg)](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/style.yml)
[![Swift macOS](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/swift-macos.yml/badge.svg)](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/swift-macos.yml)
[![Swift Linux](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/swift-linux.yml/badge.svg)](https://github.com/mihaelamj/OpenAPIDoctor/actions/workflows/swift-linux.yml)

Diagnose and repair OpenAPI 3.x specs with the same parser
`swift-openapi-generator` uses.

## What it does

OpenAPIDoctor decodes an OpenAPI 3.0 or 3.1 document through
[`mattpolzin/OpenAPIKit`](https://github.com/mattpolzin/OpenAPIKit)
(the same library `swift-openapi-generator` builds on) and surfaces
every parse failure as a structured `Diagnosis` value. Use the library
to validate specs from code, or the bundled `openapi-doctor` CLI in
shell pipelines.

Multi-file specs (with external `$ref` references across folders) are
auto-resolved via
[Stitcher](https://github.com/mihaelamj/Stitcher) before validation,
so the same entry point handles both single-file and multi-file
shapes.

## Why

Real-world OpenAPI specs accumulate small violations as they're
hand-edited and copy-pasted across tools: stray keys on `Parameter`
and `Tag` objects, the deprecated `nullable: true` keyword on a 3.1
spec, `application/x-www-form-urlencoded` response content types that
the Swift OpenAPI runtime can't serve. OpenAPIKit's strict parser
surfaces every one of these as an `InconsistencyError`, but without
structured access to those failures, callers either drop them on the
floor (emitting non-compiling generated code) or stop at the first
error.

OpenAPIDoctor turns every diagnosis into a typed value the caller can
act on:

- `vendorExtensionPrefix`: auto-repairable; the caller is given the
  exact `codingPath` and `invalidKeys` to strip.
- `inconsistency`: other OpenAPIKit-level violations; needs human
  attention.
- `decodingError`: Foundation-level type mismatches; needs human
  attention.
- `fileError` / `unknown`: escape hatches.

## Install

Add as a Swift Package Manager dependency:

```swift
.package(url: "https://github.com/mihaelamj/OpenAPIDoctor", from: "1.0.0"),
```

Target dependency:

```swift
.product(name: "OpenAPIDoctor", package: "OpenAPIDoctor"),
```

The CLI binary is built alongside the library; install it locally
with:

```bash
swift build -c release --package-path .
cp .build/release/openapi-doctor /usr/local/bin/
```

## Use from Swift

```swift
import OpenAPIDoctor

let validator = OpenAPIDoctor.Validation.Validator()
let diagnosis = try await validator.validate(at: "openapi.yaml")

switch diagnosis.kind {
case .ok:
    print("clean")
case let .vendorExtensionPrefix(codingPath, invalidKeys, subject):
    print("\(subject) at \(codingPath.joined(separator: "/")) carries \(invalidKeys)")
case let .inconsistency(codingPath, details, _):
    print("inconsistency at \(codingPath): \(details)")
case let .decodingError(codingPath, details):
    print("decoding error at \(codingPath): \(details)")
case let .fileError(details):
    print("file error: \(details)")
case let .unknown(details):
    print("unknown: \(details)")
}
```

## Use from the shell

```bash
$ openapi-doctor --help
openapi-doctor: diagnose and repair OpenAPI 3.x specs
...

$ openapi-doctor openapi.yaml
{"status":"ok"}

$ openapi-doctor openapi-with-stray-keys.yaml
{"codingPath":["tags","Index 0"],"invalidKeys":["slug","timezone"],"kind":"vendor-extension-prefix","status":"inconsistency","subject":"Vendor Extension"}

$ openapi-doctor --fix openapi-with-stray-keys.yaml
{"finalDiagnosis":"ok","rounds":[{"codingPath":["tags","Index 0"],"removedKeys":["slug","timezone"]}],"roundsApplied":1,"status":"repaired","totalRemovedKeys":2}
```

### Flags

| Flag | Meaning |
|------|---------|
| `--fix` | Auto-repair `vendor-extension-prefix` violations in place (rewrites the spec file). |
| `--output <path>` | With `--fix`, write the repaired YAML to `<path>` instead of overwriting the source. |
| `--all` | Validate iteratively, surface every fixable diagnosis (dry-run, no rewrite). |
| `--corpus` | Treat the argument as a directory; validate every YAML/JSON spec under it recursively. |
| `--no-resolve-refs` | Skip Stitcher; load the spec file as-is and don't follow external `$ref`s. Useful when referenced files aren't available locally. |
| `-h`, `--help` | Print the help message and exit 0. |

### Corpus mode

```bash
$ openapi-doctor --corpus ./specs
# stderr: one JSON per spec, including the spec path
# stdout: aggregate summary
{"clean":13,"fileError":0,"fixable":3,"nonFixable":2,"status":"corpus","totalSpecs":18,"unknown":0}
```

Exit code: 0 if all clean, 1 if some are fixable but none are non-fixable, 2 otherwise.

### Exit codes (validate mode)

| Code | Meaning |
|------|---------|
| `0` | Spec parses cleanly |
| `1` | Recoverable error: caller can auto-repair with `--fix` |
| `2` | Non-recoverable error: user must edit the spec |

### Exit codes (`--fix` mode)

| Code | Meaning |
|------|---------|
| `0` | Repair succeeded; final spec is clean |
| `1` | Partial repair; the remaining diagnosis isn't auto-fixable |
| `2` | File or unknown error |

## A note on the "given data was not valid YAML" message

Yams's `YAMLDecoder` wraps every error thrown during nested decoding
inside `DecodingError.dataCorrupted` with that misleading message.
The true cause lives in `Context.underlyingError`. OpenAPIDoctor walks
that chain so callers see the actual OpenAPIKit error, not Yams's
generic wrapper.

## Contributing and community

- [Contributing guide](CONTRIBUTING.md): setup, conventions, commit and PR rules.
- [Code of Conduct](CODE_OF_CONDUCT.md): the standard we hold the community to.
- [Security policy](SECURITY.md): how to report a vulnerability privately.
- [Support](SUPPORT.md): where to ask questions and file reports.
- [Changelog](CHANGELOG.md): notable changes per release.

Bug reports and feature requests use the issue forms under
[New issue](https://github.com/mihaelamj/OpenAPIDoctor/issues/new/choose). CI runs
the style, format, lint, build, and test gates on macOS and Linux for every push
and pull request.

## License

MIT. See `LICENSE`.
