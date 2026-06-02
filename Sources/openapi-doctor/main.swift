// openapi-doctor CLI
//
// Wrapper around `OpenAPIDoctor.Validation.Validator` and
// `OpenAPIDoctor.Repair.Repairer`. See `openapi-doctor --help` for the
// full usage; see the package README + DocC catalogue for the JSON
// output shapes and per-mode exit codes.

import Foundation
import OpenAPIDoctor

let kUsage = """
openapi-doctor: diagnose and repair OpenAPI 3.x specs

USAGE:
    openapi-doctor [OPTIONS] <spec>

ARGUMENTS:
    <spec>                Path to an OpenAPI 3.0 or 3.1 spec (YAML or JSON).

OPTIONS:
    --fix                 Auto-repair `vendor-extension-prefix` violations.
                          Rewrites the spec file in place by default. Streams
                          one JSON object per round to stderr; emits a final
                          summary on stdout.
    --output <path>       Write the repaired YAML to <path> instead of
                          overwriting the source. Only meaningful with --fix.
                          The source file stays untouched.
    --all                 In validate mode, surface EVERY fixable diagnosis
                          (dry-run: doesn't write back). Streams one JSON
                          object per diagnosis to stderr; emits a final
                          summary on stdout. Useful for surveying a spec
                          before deciding to --fix.
    --corpus              Treat <path> as a directory and validate every
                          OpenAPI spec under it (recurses; matches *.yaml,
                          *.yml, *.json). Streams one JSON per spec to
                          stderr; emits an aggregate summary on stdout.
    --no-resolve-refs     Skip Stitcher; load the spec file as-is and do not
                          follow external `$ref`s. Useful when the referenced
                          files aren't available locally.
    -h, --help            Print this help message and exit.

EXAMPLES:
    openapi-doctor openapi.yaml
        Validate (read-only). Prints a single-line JSON diagnosis on stdout.

    openapi-doctor --all openapi.yaml
        Validate iteratively. Streams one JSON per discovered diagnosis to
        stderr; final summary on stdout.

    openapi-doctor --fix openapi.yaml
        Validate + repair in place. Streams one JSON per round to stderr;
        final summary on stdout. The spec file is rewritten.

    openapi-doctor --fix openapi.yaml --output fixed.yaml
        Validate + repair, write the result to `fixed.yaml`. The source
        spec at `openapi.yaml` stays unchanged.

    openapi-doctor --corpus ./specs
        Validate every *.yaml / *.yml / *.json under ./specs (recursive).
        Streams one JSON per spec to stderr; aggregate summary on stdout.

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
    stdout: one final JSON object summarising the result.
    stderr: in --fix and --all modes, one JSON object per
             round/diagnosis as it's discovered (JSON Lines stream).
"""

func usageExit(toStderr: Bool = false, code: Int32 = 2) -> Never {
    if toStderr {
        FileHandle.standardError.write(Data((kUsage + "\n").utf8))
    } else {
        print(kUsage)
    }
    exit(code)
}

func emitToStderr(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

let args = Array(CommandLine.arguments.dropFirst())

if args.contains("-h") || args.contains("--help") {
    usageExit(toStderr: false, code: 0)
}

let shouldFix = args.contains("--fix")
let shouldShowAll = args.contains("--all")
let isCorpus = args.contains("--corpus")
let resolveRefs = !args.contains("--no-resolve-refs")

// Pull --output <path> out of argv. Positional arg list is whatever
// remains after dropping flags + their values.
var outputPath: String?
var positional: [String] = []
var skipNext = false
for (idx, arg) in args.enumerated() {
    if skipNext { skipNext = false
        continue
    }
    if arg == "--output" {
        guard idx + 1 < args.count else {
            FileHandle.standardError.write(Data("openapi-doctor: --output requires a path argument\n".utf8))
            exit(2)
        }
        outputPath = args[idx + 1]
        skipNext = true
        continue
    }
    if arg.hasPrefix("-") {
        continue // a flag without a value (--fix, --all, --no-resolve-refs)
    }
    positional.append(arg)
}

guard positional.count == 1 else {
    usageExit(toStderr: true, code: 2)
}

let path = positional[0]

if shouldFix, shouldShowAll {
    FileHandle.standardError.write(Data("openapi-doctor: --fix and --all are mutually exclusive\n".utf8))
    exit(2)
}

if isCorpus, shouldFix || shouldShowAll {
    FileHandle.standardError.write(Data("openapi-doctor: --corpus is mutually exclusive with --fix and --all\n".utf8))
    exit(2)
}

if outputPath != nil, !shouldFix {
    FileHandle.standardError.write(Data("openapi-doctor: --output requires --fix\n".utf8))
    exit(2)
}

if isCorpus {
    // Recursively walk `path`, validate every YAML/JSON spec, stream per-
    // file diagnoses to stderr, emit aggregate summary on stdout.
    let manager = FileManager.default
    var isDir: ObjCBool = false
    guard manager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
        print(#"{"status":"file_error","details":"\#(path) is not a directory"}"#)
        exit(2)
    }

    var specs: [String] = []
    if let enumerator = manager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isRegularFileKey]) {
        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard ext == "yaml" || ext == "yml" || ext == "json" else { continue }
            let values = (try? url.resourceValues(forKeys: [.isRegularFileKey])) ?? URLResourceValues()
            if values.isRegularFile == true {
                specs.append(url.path)
            }
        }
    }
    specs.sort()

    let validator = OpenAPIDoctor.Validation.Validator()
    var clean = 0, fixable = 0, nonFixable = 0, fileError = 0, unknownCount = 0
    for spec in specs {
        let diagnosis: OpenAPIDoctor.Validation.Diagnosis
        do {
            diagnosis = try await validator.validate(at: spec, resolveExternalRefs: resolveRefs)
        } catch {
            diagnosis = .init(kind: .fileError(details: error.localizedDescription))
        }
        var line = diagnosis.toJSON()
        // Splice the spec path into the JSON for cross-reference
        if line.hasPrefix("{") {
            // Escape forward slashes in the path the same way Foundation does
            let escapedPath = spec.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            line = "{\"spec\":\"\(escapedPath)\"," + String(line.dropFirst())
        }
        emitToStderr(line)
        switch diagnosis.kind {
        case .ok: clean += 1
        case .vendorExtensionPrefix, .missingServers, .missingOperationId: fixable += 1
        case .inconsistency, .decodingError: nonFixable += 1
        case .fileError: fileError += 1
        case .unknown: unknownCount += 1
        }
    }

    let total = specs.count
    let summary: [String: Any] = [
        "status": "corpus",
        "totalSpecs": total,
        "clean": clean,
        "fixable": fixable,
        "nonFixable": nonFixable,
        "fileError": fileError,
        "unknown": unknownCount,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
       let str = String(data: data, encoding: .utf8)
    {
        print(str)
    }
    // Exit code: 0 if all clean, 1 if some fixable but none non-fixable, 2 otherwise
    if total == clean { exit(0) }
    if nonFixable == 0, fileError == 0, unknownCount == 0 { exit(1) }
    exit(2)
}

if shouldFix {
    var roundIdx = 0
    let onRound: (OpenAPIDoctor.Repair.RepairRound) -> Void = { round in
        roundIdx += 1
        var payload: [String: Any] = [
            "round": roundIdx,
            "kind": round.kind.rawValue,
            "codingPath": round.codingPath,
            "removedKeys": round.removedKeys,
        ]
        if round.injectedDefaultServers {
            payload["injectedDefaultServers"] = true
        }
        if let id = round.synthesizedOperationId {
            payload["synthesizedOperationId"] = id
        }
        if let idx = round.collisionIndex {
            payload["collisionIndex"] = idx
        }
        if let opPath = round.opPath {
            payload["path"] = opPath
        }
        if let opMethod = round.opMethod {
            payload["method"] = opMethod
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8)
        {
            emitToStderr(line)
        }
    }

    do {
        let repairer = OpenAPIDoctor.Repair.Repairer()
        if let outputPath {
            // Load + repair purely, then write to outputPath. The source
            // file at `path` stays unchanged.
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let sourceYAML = try await loader.load(from: path, resolveExternalRefs: resolveRefs)
            let (repaired, result) = await repairer.repair(yaml: sourceYAML, onRound: onRound)
            try repaired.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print(result.toJSON())
            exit(result.isClean ? 0 : 1)
        } else {
            // In-place: writes back to `path` if any round ran.
            let result = try await repairer.repair(
                at: path,
                resolveExternalRefs: resolveRefs,
                onRound: onRound
            )
            print(result.toJSON())
            exit(result.isClean ? 0 : 1)
        }
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
} else if shouldShowAll {
    let validator = OpenAPIDoctor.Validation.Validator()
    let loader = OpenAPIDoctor.Loading.SpecLoader()
    let yaml: String
    do {
        yaml = try await loader.load(from: path, resolveExternalRefs: resolveRefs)
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
    var diagnosisIdx = 0
    let diagnoses = await validator.collectAll(yaml: yaml, onDiagnosis: { diagnosis in
        diagnosisIdx += 1
        var line = diagnosis.toJSON()
        // Splice the index into the JSON: insert "index":N as the first key
        if line.hasPrefix("{") {
            line = "{\"index\":\(diagnosisIdx)," + String(line.dropFirst())
        }
        emitToStderr(line)
    })
    // Emit a summary that counts diagnoses by category.
    var fixableCount = 0
    var terminalKind = "ok"
    for diagnosis in diagnoses {
        switch diagnosis.kind {
        case .vendorExtensionPrefix, .missingServers, .missingOperationId:
            fixableCount += 1
        default:
            break
        }
    }
    if let last = diagnoses.last {
        switch last.kind {
        case .ok: terminalKind = "ok"
        case .vendorExtensionPrefix: terminalKind = "vendor-extension-prefix"
        case .missingServers: terminalKind = "missing-servers"
        case .missingOperationId: terminalKind = "missing-operation-id"
        case .inconsistency: terminalKind = "inconsistency"
        case .decodingError: terminalKind = "decoding_error"
        case .fileError: terminalKind = "file_error"
        case .unknown: terminalKind = "unknown_error"
        }
    }
    let summary: [String: Any] = [
        "status": terminalKind == "ok" ? "ok" : "incomplete",
        "diagnosesFound": diagnoses.count,
        "fixableDiagnoses": fixableCount,
        "terminalKind": terminalKind,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8)
    {
        print(line)
    }
    exit(terminalKind == "ok" ? 0 : (fixableCount > 0 ? 1 : 2))
} else {
    do {
        let validator = OpenAPIDoctor.Validation.Validator()
        let diagnosis = try await validator.validate(at: path, resolveExternalRefs: resolveRefs)
        print(diagnosis.toJSON())
        switch diagnosis.kind {
        case .ok:
            exit(0)
        case .vendorExtensionPrefix, .missingServers, .missingOperationId:
            exit(1)
        case .inconsistency, .decodingError, .fileError, .unknown:
            exit(2)
        }
    } catch {
        print(#"{"status":"file_error","details":"\#(error.localizedDescription)"}"#)
        exit(2)
    }
}
