// openapi-doctor CLI
//
// Thin wrapper around `OpenAPIDoctor.Validation.Validator`. Takes a
// spec path on argv and emits a single-line JSON diagnosis on stdout.
//
// Exit codes:
//   0 — spec parses cleanly
//   1 — recoverable error (orchestrator can auto-repair)
//   2 — non-recoverable error (user must fix)

import Foundation
import OpenAPIDoctor

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: openapi-doctor <spec.yaml | spec.json>\n".utf8))
    print(#"{"status":"usage_error","details":"expected one argument: path to spec"}"#)
    exit(2)
}

let path = CommandLine.arguments[1]
let validator = OpenAPIDoctor.Validation.Validator()

let diagnosis = try await validator.validate(at: path)
print(diagnosis.toJSON())

switch diagnosis.kind {
case .ok:
    exit(0)
case .vendorExtensionPrefix:
    exit(1)
case .inconsistency, .decodingError, .fileError, .unknown:
    exit(2)
}
