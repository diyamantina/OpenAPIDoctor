# ``OpenAPIDoctor``

Diagnose and repair OpenAPI 3.x specs with the same parser
`swift-openapi-generator` uses.

@Metadata {
    @DisplayName("OpenAPIDoctor")
}

## Overview

OpenAPIDoctor decodes an OpenAPI 3.0 or 3.1 document through
[`mattpolzin/OpenAPIKit`](https://github.com/mattpolzin/OpenAPIKit)
and categorises every parse failure into a structured
``Validation/Diagnosis``. The library also bundles an `openapi-doctor`
command-line executable for use in CI, pre-commit hooks, or scaffolding
pipelines.

Real-world OpenAPI specs accumulate small structural violations as
they're hand-edited and copy-pasted across tools: stray keys on
`Parameter` and `Tag` objects, the deprecated `nullable: true` keyword
on a 3.1 spec, `application/x-www-form-urlencoded` response content
types that the Swift OpenAPI runtime can't serve. OpenAPIKit's strict
parser surfaces every one of these as an `InconsistencyError`. Without
structured access to those failures, callers either drop them on the
floor (silently emitting non-compiling generated code) or stop at the
first error (forcing edit / rerun loops). OpenAPIDoctor surfaces every
diagnosis as a typed value so callers can choose to auto-repair,
prompt the user, or abort with a clear message.

Multi-file specs (with external `$ref` references across folders) are
auto-resolved via [Stitcher](https://github.com/mihaelamj/Stitcher)
before validation, so the same library handles single-file and
multi-file specs through one entry point.

## Configure the sample code project

Add OpenAPIDoctor as a package dependency:

```swift
.package(url: "https://github.com/mihaelamj/OpenAPIDoctor", from: "0.1.0"),
```

Validate a spec from anywhere in your code:

```swift
import OpenAPIDoctor

let validator = OpenAPIDoctor.Validation.Validator()
let diagnosis = try await validator.validate(at: "openapi.yaml")
if diagnosis.isClean {
    print("Spec parses cleanly.")
} else {
    print(diagnosis)  // CustomStringConvertible
}
```

To use the CLI in a shell pipeline:

```bash
swift run openapi-doctor openapi.yaml
# {"status":"ok"}

swift run openapi-doctor openapi-with-stray-keys.yaml
# {"codingPath":["tags","Index 0"],"invalidKeys":["branding","slug"],"kind":"vendor-extension-prefix","status":"inconsistency","subject":"Vendor Extension"}
```

Exit codes:

| Code | Meaning |
|------|---------|
| `0` | Spec parses cleanly |
| `1` | Recoverable error: caller can auto-repair |
| `2` | Non-recoverable error: user must edit the spec |

## Diagnosing a spec

The validator returns a ``Validation/Diagnosis`` value with two
properties of interest: `kind` (the structured outcome) and
`isAutoRepairable` (whether the outcome can be fixed mechanically).

```swift
let diagnosis = await validator.validate(at: "openapi.yaml")

switch diagnosis.kind {
case .ok:
    print("clean")

case let .vendorExtensionPrefix(codingPath, invalidKeys, subjectName):
    print("\(subjectName) at \(codingPath.joined(separator: "/")) carries \(invalidKeys)")

case let .inconsistency(codingPath, details, _):
    print("OpenAPIKit inconsistency at \(codingPath): \(details)")

case let .decodingError(codingPath, details):
    print("Foundation decoding error at \(codingPath): \(details)")

case let .fileError(details):
    print("file error: \(details)")

case let .unknown(details):
    print("unknown error: \(details)")
}
```

## Why Yams's "given data was not valid YAML" message is misleading

Yams's `YAMLDecoder` wraps every error thrown during nested decoding
inside `DecodingError.dataCorrupted` with the misleading message
"The given data was not valid YAML." The true cause typically lives
one level deeper, in `Context.underlyingError`. OpenAPIDoctor walks
that chain to find OpenAPIKit's wrapped `InconsistencyError` and
surfaces its `subjectName`, `codingPath`, and parsed `invalidKeys` so
callers see the actual problem.

This bookkeeping is invisible from the outside (every error you can
reasonably get from a spec is already typed in
``Validation/DiagnosisKind``), but it's worth knowing when reading
the source.

## Repairing a spec

Auto-repair is a separate decision the caller makes. When
``Validation/Diagnosis/isAutoRepairable`` is `true`, the caller has
enough information to fix the spec without further input. For the
common `vendorExtensionPrefix` case:

```swift
case let .vendorExtensionPrefix(codingPath, invalidKeys, _):
    // Walk the YAML to `codingPath`, delete `invalidKeys`, re-validate.
    var doc = loadYAML(from: path)
    walkAndDelete(doc, at: codingPath, keys: invalidKeys)
    save(doc, to: path)
    // Loop: validate again.
```

OpenAPIDoctor stops at one diagnosis per pass. Callers that want
exhaustive repair (the orchestrator pattern in
[`codeweaver-skills`](https://github.com/mihaelamj/codeweaver-skills))
run validate → repair → revalidate in a loop until `isClean` is
`true`.

## Topics

### Core API

- ``Validation/Validator``
- ``Validation/Diagnosis``
- ``Validation/DiagnosisKind``

### Loading

- ``Loading/SpecLoader``
