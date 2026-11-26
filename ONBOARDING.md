# Onboarding

## Purpose

OpenAPIDoctor checks an OpenAPI 3.0, 3.1 or 3.2 document, lists what is wrong in words a person can act on, and repairs what it safely can.

## State on 2026-11-26

Host main before this note: `321a31f`. Nothing is unfinished or only local.

## Done on 2026-11-26

- A fault that makes a document invalid is reported before the advice about `servers` and `operationId`.
- New checks: an operation id used twice, `nullable` in 3.1 and later, a lower bound above its upper bound.
- `OpenAPIDoctor.Report`: every finding with line, fault, fix, rule, YAML example and plain explanation; `openapi-doctor --report`.
- `OpenAPIDoctor.Report.Fixer`: line edits, offered only when examining the result shows the finding gone. A test runs fix all over the corpus documents and holds that none is damaged.
- OpenAPIKit 7.0.0. A 3.0 document is checked in its 3.1 form, in memory only; no fix changes the version line. Old and new versions were compared on the 3.0 test documents: nothing lost, nothing new.

## Next steps, in order

1. A release tag and release notes (not made; needs the owner's word).
2. A safe fix for a `$ref` where none is allowed (four such places in the corpus), if one can be defined.
3. Findings one at a time: the typed reading gives one fault of a part per pass. Reading smaller pieces would list more at once.
4. A build for iOS has not been tried.

## Build, test, push

- `swift build`, `swift test`; `scripts/check-style.sh`, `scripts/check-namespacing.sh`; `swiftformat --lint .`, `swiftlint lint`.
- Point the scratch and cache folders of SwiftPM at an external disk.
- The repository is public: read the outgoing change for private names before every push. Push fast forward only and read the hash back from the host.
- A change in what a user sees, above all in what a fix does to a file, is agreed with the owner before it is pushed.

## Traps

- Decoding a part of a document on its own with an empty coding path crashes inside the parsing library; pass the path from the top of the document.
- A line end of two characters is one `Character` in Swift: split on `\.isNewline`, not on `"\n"`.
- `swift package resolve` warns that the YAML library is named by two addresses (this package and one of its dependencies). The owner has not decided how it is fetched; leave it.
- OpenAPIKit 7 checks no 3.0 document itself; the conversion in `Validator` is what runs the checks.
