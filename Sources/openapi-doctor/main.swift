// openapi-doctor CLI
//
// Wrapper around `OpenAPIDoctor.Validation.Validator` and
// `OpenAPIDoctor.Repair.Repairer`.
//
// Usage:
//   openapi-doctor <spec>          — validate; emit one-line JSON diagnosis
//   openapi-doctor --fix <spec>    — validate + repair (in-place); emit JSON summary
//
// Exit codes (validate mode):
//   0 — spec parses cleanly
//   1 — recoverable error (caller can auto-repair with --fix)
//   2 — non-recoverable error (user must fix the spec)
//
// Exit codes (--fix mode):
//   0 — repair succeeded (final diagnosis is .ok)
//   1 — repair stopped because the next diagnosis isn't auto-fixable
//   2 — file or unknown error

import Foundation
import OpenAPIDoctor

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: openapi-doctor [--fix] <spec.yaml | spec.json>\n".utf8))
    print(#"{"status":"usage_error","details":"expected one path argument; optional --fix flag"}"#)
    exit(2)
}

guard !args.isEmpty else { usage() }

let shouldFix = args.contains("--fix")
let pathArg = args.first { $0 != "--fix" }
guard let path = pathArg else { usage() }

if shouldFix {
    do {
        let repairer = OpenAPIDoctor.Repair.Repairer()
        let result = try await repairer.repair(at: path)
        print(result.toJSON())
        if result.isClean {
            exit(0)
        }
        // Repair stopped before fully clean — non-fixable diagnosis remaining.
        exit(1)
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
} else {
    let validator = OpenAPIDoctor.Validation.Validator()
    do {
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
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
}
