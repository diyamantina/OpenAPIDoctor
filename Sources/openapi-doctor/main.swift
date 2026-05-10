// openapi-doctor CLI
//
// Wrapper around `OpenAPIDoctor.Validation.Validator` and
// `OpenAPIDoctor.Repair.Repairer`. See `openapi-doctor --help` for the
// full usage; see the package README + DocC catalogue for the JSON
// output shapes and per-mode exit codes.

import Foundation
import OpenAPIDoctor

let kUsage = """
openapi-doctor — diagnose and repair OpenAPI 3.x specs

USAGE:
    openapi-doctor [OPTIONS] <spec>

ARGUMENTS:
    <spec>                Path to an OpenAPI 3.0 or 3.1 spec (YAML or JSON).

OPTIONS:
    --fix                 Auto-repair `vendor-extension-prefix` violations in
                          place (rewrites the spec file).
    --no-resolve-refs     Skip Stitcher; load the spec file as-is and do not
                          follow external `$ref`s. Useful when the referenced
                          files aren't available locally.
    -h, --help            Print this help message and exit.

EXAMPLES:
    openapi-doctor openapi.yaml
        Validate (read-only). Prints a single-line JSON diagnosis.

    openapi-doctor --fix openapi.yaml
        Validate + repair in place. Rewrites the file with the auto-fixable
        violations removed.

    openapi-doctor --no-resolve-refs api.yml
        Validate a single file without trying to resolve external refs.

EXIT CODES (validate mode):
    0   Spec parses cleanly.
    1   Recoverable error (use --fix to auto-repair).
    2   Non-recoverable error (edit the spec yourself).

EXIT CODES (--fix mode):
    0   Repair succeeded; final spec is clean.
    1   Partial repair; the remaining diagnosis isn't auto-fixable.
    2   File or unknown error.

OUTPUT:
    A single JSON object on stdout describing the result. See the package
    README for the full shape per case.
"""

func usageExit(toStderr: Bool = false, code: Int32 = 2) -> Never {
    if toStderr {
        FileHandle.standardError.write(Data((kUsage + "\n").utf8))
    } else {
        print(kUsage)
    }
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("-h") || args.contains("--help") {
    usageExit(toStderr: false, code: 0)
}

let shouldFix = args.contains("--fix")
let resolveRefs = !args.contains("--no-resolve-refs")
let positional = args.filter { !$0.hasPrefix("-") }

guard positional.count == 1 else {
    usageExit(toStderr: true, code: 2)
}
let path = positional[0]

if shouldFix {
    do {
        let repairer = OpenAPIDoctor.Repair.Repairer()
        let result = try await repairer.repair(at: path, resolveExternalRefs: resolveRefs)
        print(result.toJSON())
        exit(result.isClean ? 0 : 1)
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
} else {
    do {
        let validator = OpenAPIDoctor.Validation.Validator()
        let diagnosis = try await validator.validate(at: path, resolveExternalRefs: resolveRefs)
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
