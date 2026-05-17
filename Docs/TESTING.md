# How to test OpenAPIDoctor against bad specs

Hands-on walkthrough using the fixtures shipped with the package
(`Tests/OpenAPIDoctorTests/Fixtures/`) plus a real-world spec from
your `mihaela-mvp-shop` repo.

Build the CLI once:

```bash
cd /Volumes/Code/DeveloperExt/public/OpenAPIDoctor
swift build -c release
PATH="$PWD/.build/release:$PATH"
# Now `openapi-doctor` is available as a shell command in this terminal.
```

Or use `swift run -q openapi-doctor ...` if you prefer not to put it
on PATH.

## Fixtures shipped in the package

| Fixture | What's wrong | Expected doctor verdict |
|---|---|---|
| `Fixtures/clean.yaml` | Nothing | `status: ok`, exit 0 |
| `Fixtures/clean-3.0.yaml` | Nothing (OpenAPI 3.0 variant) | `status: ok`, exit 0 |
| `Fixtures/stray-tag-keys.yaml` | A `Tag` object carries `slug:` and `timezone:` (non-`x-` keys) | `vendor-extension-prefix`, fixable, exit 1 |
| `Fixtures/stray-parameter-keys.yaml` | A `Parameter` carries `email: null, phone: null` | `vendor-extension-prefix`, fixable, exit 1 |
| `Fixtures/multi-stray.yaml` | Two `Tag` objects with three stray keys total | `vendor-extension-prefix` repeated, all fixable, exit 1 |
| `Fixtures/missing-required.yaml` | `info:` block is missing the required `title:` field | `decoding_error`, non-fixable, exit 2 |
| `Fixtures/financeexample/<service>/spec.yml` | 22 multi-file FinTech specs, anonymised — all clean, exercise Stitcher | `status: ok`, exit 0 |

## Try each case

### Case 1 — clean spec (baseline)

```bash
openapi-doctor Tests/OpenAPIDoctorTests/Fixtures/clean.yaml
# {"status":"ok"}
# exit 0
```

### Case 2 — single stray-key violation

```bash
openapi-doctor Tests/OpenAPIDoctorTests/Fixtures/stray-tag-keys.yaml
# {"codingPath":["tags","Index 0"],"invalidKeys":["slug","timezone"],"kind":"vendor-extension-prefix","status":"inconsistency","subject":"Vendor Extension"}
# exit 1
```

### Case 3 — multiple violations, dry-run survey via `--all`

```bash
openapi-doctor --all Tests/OpenAPIDoctorTests/Fixtures/multi-stray.yaml 2>/tmp/diagnoses.jsonl
# stdout: {"diagnosesFound":3,"fixableDiagnoses":2,"status":"ok","terminalKind":"ok"}

cat /tmp/diagnoses.jsonl
# {"index":1,"codingPath":["tags","Index 0"],"invalidKeys":["slug"],...}
# {"index":2,"codingPath":["tags","Index 1"],"invalidKeys":["timezone","region"],...}
# {"index":3,"status":"ok"}
```

### Case 4 — auto-repair in place

```bash
# Always copy first if you want the source preserved
cp Tests/OpenAPIDoctorTests/Fixtures/multi-stray.yaml /tmp/test-fix.yaml
openapi-doctor --fix /tmp/test-fix.yaml
# stderr: round 1 ... round 2 ...
# stdout: {"finalDiagnosis":"ok","rounds":[...],"roundsApplied":2,"status":"repaired","totalRemovedKeys":3}
# /tmp/test-fix.yaml is now clean. Re-validate to confirm:
openapi-doctor /tmp/test-fix.yaml
# {"status":"ok"}
```

### Case 5 — auto-repair to a different file (source preserved)

```bash
openapi-doctor --fix Tests/OpenAPIDoctorTests/Fixtures/multi-stray.yaml --output /tmp/repaired.yaml
# Same JSON output, but the original fixture is untouched
# and the repaired YAML lives at /tmp/repaired.yaml.
diff Tests/OpenAPIDoctorTests/Fixtures/multi-stray.yaml /tmp/repaired.yaml
# (shows what got stripped)
```

### Case 6 — non-fixable violation

```bash
openapi-doctor Tests/OpenAPIDoctorTests/Fixtures/missing-required.yaml
# {"codingPath":[...],"details":"...key not found: title...","status":"decoding_error"}
# exit 2
```

`--fix` on this one won't help — the doctor can't invent a missing
`title:` field. Exit 1 in `--fix` mode (partial repair: no rounds ran).

### Case 7 — missing file

```bash
openapi-doctor /this/path/does/not/exist.yaml
# {"details":"The file 'exist.yaml' couldn't be opened because there is no such file.","status":"file_error"}
# exit 2
```

### Case 8 — multi-file spec with cross-folder `$ref`s (Stitcher exercise)

```bash
openapi-doctor Tests/OpenAPIDoctorTests/Fixtures/financeexample/analytics/spec.yml
# {"status":"ok"}
# Stitcher resolved ../core/schemas/apiError.yml, ./schemas/leadEvent.yml,
# etc. into one document before the validator saw it.
```

To prove Stitcher is doing real work, try `--no-resolve-refs`:

```bash
openapi-doctor --no-resolve-refs Tests/OpenAPIDoctorTests/Fixtures/financeexample/analytics/spec.yml
# This time the doctor reads only analytics/spec.yml — every `$ref:
# ../core/...` is left dangling, and OpenAPIKit either accepts the
# bare refs (depending on schema shape) or surfaces missing-reference
# errors.
```

### Case 9 — a real-world spec with multiple violations

If you have the mihaela-mvp-shop checkout:

```bash
cp /Volumes/Code/DeveloperExt/private/mihaela-mvp-shop/templates/bookings/openapi.yaml /tmp/bookings.yaml

# Survey:
openapi-doctor --all /tmp/bookings.yaml 2>/tmp/bookings-diagnoses.jsonl
cat /tmp/bookings-diagnoses.jsonl
# 4 fixable diagnoses (1 in Parameter object, 3 in Tag objects)
# Terminal diagnosis: ok

# Repair to a side file:
openapi-doctor --fix /tmp/bookings.yaml --output /tmp/bookings-repaired.yaml
# stderr: 4 rounds streamed
# stdout: {"finalDiagnosis":"ok","roundsApplied":4,"totalRemovedKeys":9,...}

diff /tmp/bookings.yaml /tmp/bookings-repaired.yaml | head -40
# Shows exactly what got stripped.
```

## Crafting your own bad spec

To author a spec that triggers a specific diagnosis kind:

| Kind to trigger | Recipe |
|---|---|
| `vendorExtensionPrefix` (fixable) | Add a non-`x-` key to any `Parameter`, `Tag`, `Operation`, `Response`, `RequestBody`, `Header`, `SecurityScheme`, etc. Example: `tags: [{name: foo, slug: bar}]` — `slug` is the stray key. |
| `inconsistency` (non-fixable) | Set `openapi: 4.0.0` (unsupported version), or supply a malformed `$ref:` that points at an unknown component. |
| `decodingError` (non-fixable) | Remove a required field — e.g. drop `title:` from `info:`. Or supply the wrong type — `version: 1.0` instead of `version: "1.0"`. |
| `fileError` | Point the CLI at a non-existent path. |

The OpenAPIDoctor `Validator` runs every spec through OpenAPIKit's
strict decoder, so any structural violation OpenAPIKit catches surfaces
as a diagnosis. See `Sources/OpenAPIDoctor/DiagnosisKind.swift` for the
full enum.

## Library API, not CLI

If you want to drive the validator from Swift code rather than from
the shell:

```swift
import OpenAPIDoctor

// Validate
let v = OpenAPIDoctor.Validation.Validator()
let diagnosis = try await v.validate(at: "openapi.yaml")
if diagnosis.isClean { /* ... */ }

// Surface every fixable diagnosis (dry run)
let all = await v.collectAll(yaml: try String(contentsOfFile: "openapi.yaml"))
for d in all { print(d) }

// Repair (pure, no filesystem mutation)
let r = OpenAPIDoctor.Repair.Repairer()
let (repaired, result) = await r.repair(yaml: original)

// Repair in place
try await r.repair(at: "openapi.yaml")
```

## What the tests do that you should mirror

The test suite (`Tests/OpenAPIDoctorTests/`) exercises every diagnosis
kind plus the CLI:

- `ValidatorTests` — three core diagnoses from fixtures.
- `RepairerTests` — six repair scenarios including non-fixable.
- `CLITests` — sixteen CLI invocations covering every flag and exit code.
- `FinanceexampleCorpusTests` — drives the validator over 594 anonymised
  multi-file FinTech specs (22 service entry points).

Run the full suite:

```bash
swift test
# Test run with 29 tests in 4 suites passed
```
