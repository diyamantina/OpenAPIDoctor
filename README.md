# OpenAPIDoctor

Diagnose and repair OpenAPI 3.x specs with the same parser
`swift-openapi-generator` uses.

## What it does

OpenAPIDoctor decodes an OpenAPI 3.0 or 3.1 document through
[`mattpolzin/OpenAPIKit`](https://github.com/mattpolzin/OpenAPIKit) —
the same library `swift-openapi-generator` builds on — and surfaces
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

- `vendorExtensionPrefix` — auto-repairable; the caller is given the
  exact `codingPath` and `invalidKeys` to strip.
- `inconsistency` — other OpenAPIKit-level violations; needs human
  attention.
- `decodingError` — Foundation-level type mismatches; needs human
  attention.
- `fileError` / `unknown` — escape hatches.

## Install

Add as a Swift Package Manager dependency:

```swift
.package(url: "https://github.com/mihaelamj/OpenAPIDoctor", from: "0.1.0"),
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
$ openapi-doctor openapi.yaml
{"status":"ok"}

$ openapi-doctor openapi-with-stray-keys.yaml
{"codingPath":["tags","Index 0"],"invalidKeys":["slug","timezone"],"kind":"vendor-extension-prefix","status":"inconsistency","subject":"Vendor Extension"}
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0` | Spec parses cleanly |
| `1` | Recoverable error — caller can auto-repair |
| `2` | Non-recoverable error — user must edit the spec |

## A note on the "given data was not valid YAML" message

Yams's `YAMLDecoder` wraps every error thrown during nested decoding
inside `DecodingError.dataCorrupted` with that misleading message.
The true cause lives in `Context.underlyingError`. OpenAPIDoctor walks
that chain so callers see the actual OpenAPIKit error, not Yams's
generic wrapper.

## License

MIT. See `LICENSE`.
