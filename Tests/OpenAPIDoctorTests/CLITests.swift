// CLITests
//
// Exercises the `openapi-doctor` command-line binary end-to-end by
// shelling out to it via `swift run`. Each test invokes the CLI with
// real argv, captures stdout / stderr / exit code, and asserts the
// shape of the output JSON or exit behaviour.
//
// `swift run -c debug -q` is used to avoid rebuild noise in test
// output; first invocation is slow because SPM may compile the
// executable on demand. Tests after the first one reuse the cached
// build.

import Foundation
import Testing

@testable import OpenAPIDoctor

@Suite("openapi-doctor CLI")
struct CLITests {

    // MARK: - --help flag

    @Test("--help prints usage to stdout and exits 0")
    func helpFlag() throws {
        let r = try Self.runCLI(["--help"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("USAGE:"))
        #expect(r.stdout.contains("--fix"))
        #expect(r.stdout.contains("--no-resolve-refs"))
        #expect(r.stdout.contains("openapi-doctor"))
    }

    @Test("-h is an alias for --help")
    func shortHelpFlag() throws {
        let r = try Self.runCLI(["-h"])
        #expect(r.exitCode == 0)
        #expect(r.stdout.contains("USAGE:"))
    }

    // MARK: - Missing-argument behaviour

    @Test("No arguments prints usage to stderr and exits 2")
    func noArguments() throws {
        let r = try Self.runCLI([])
        #expect(r.exitCode == 2)
        #expect(r.stderr.contains("USAGE:"))
    }

    // MARK: - Validate mode

    @Test("Validate a clean spec emits {\"status\":\"ok\"} and exits 0")
    func validateClean() throws {
        let path = try Self.fixturePath("clean.yaml")
        let r = try Self.runCLI([path])
        #expect(r.exitCode == 0)
        let json = try Self.parseJSON(r.stdout)
        #expect(json["status"] as? String == "ok")
    }

    @Test("Validate a stray-keys spec emits vendor-extension-prefix and exits 1")
    func validateFixable() throws {
        let path = try Self.fixturePath("stray-tag-keys.yaml")
        let r = try Self.runCLI([path])
        #expect(r.exitCode == 1)
        let json = try Self.parseJSON(r.stdout)
        #expect(json["status"] as? String == "inconsistency")
        #expect(json["kind"] as? String == "vendor-extension-prefix")
        let invalidKeys = (json["invalidKeys"] as? [String]) ?? []
        #expect(Set(invalidKeys) == ["slug", "timezone"])
    }

    @Test("Validate a missing-required spec exits 2 (non-fixable)")
    func validateNonFixable() throws {
        let path = try Self.fixturePath("missing-required.yaml")
        let r = try Self.runCLI([path])
        #expect(r.exitCode == 2)
        let json = try Self.parseJSON(r.stdout)
        let status = json["status"] as? String ?? ""
        #expect(status == "decoding_error" || status == "inconsistency")
    }

    @Test("Validate a missing file emits file_error and exits 2")
    func validateMissingFile() throws {
        let r = try Self.runCLI(["/this/path/does/not/exist.yaml"])
        #expect(r.exitCode == 2)
        let json = try Self.parseJSON(r.stdout)
        #expect(json["status"] as? String == "file_error")
    }

    // MARK: - --fix mode

    @Test("--fix on a stray-keys spec emits repaired summary and exits 0")
    func fixStrayKeys() throws {
        let path = try Self.copyFixtureToTemp("stray-tag-keys.yaml")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try Self.runCLI(["--fix", path])
        #expect(r.exitCode == 0)
        let json = try Self.parseJSON(r.stdout)
        #expect(json["status"] as? String == "repaired")
        #expect((json["roundsApplied"] as? Int) ?? 0 == 1)
        #expect((json["totalRemovedKeys"] as? Int) ?? 0 == 2)
        // File should be repaired in place; re-validate it
        let r2 = try Self.runCLI([path])
        #expect(r2.exitCode == 0)
    }

    @Test("--fix on a multi-stray spec applies multiple rounds")
    func fixMultiStray() throws {
        let path = try Self.copyFixtureToTemp("multi-stray.yaml")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try Self.runCLI(["--fix", path])
        #expect(r.exitCode == 0)
        let json = try Self.parseJSON(r.stdout)
        #expect((json["roundsApplied"] as? Int) ?? 0 >= 2)
        #expect((json["totalRemovedKeys"] as? Int) ?? 0 == 3)
    }

    @Test("--fix on a clean spec is a no-op and exits 0")
    func fixCleanSpec() throws {
        let path = try Self.copyFixtureToTemp("clean.yaml")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try Self.runCLI(["--fix", path])
        #expect(r.exitCode == 0)
        let json = try Self.parseJSON(r.stdout)
        #expect((json["roundsApplied"] as? Int) ?? 0 == 0)
    }

    // MARK: - --no-resolve-refs flag

    @Test("--no-resolve-refs validates the file as-is without Stitcher")
    func noResolveRefsClean() throws {
        let path = try Self.fixturePath("clean.yaml")
        let r = try Self.runCLI(["--no-resolve-refs", path])
        #expect(r.exitCode == 0)
        let json = try Self.parseJSON(r.stdout)
        #expect(json["status"] as? String == "ok")
    }

    // MARK: - Streaming per-round output

    @Test("--fix streams one JSON line per round to stderr")
    func fixStreamsPerRound() throws {
        let path = try Self.copyFixtureToTemp("multi-stray.yaml")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let r = try Self.runCLI(["--fix", path])
        #expect(r.exitCode == 0)
        let lines = r.stderr.split(separator: "\n").map(String.init)
        #expect(lines.count >= 2, "expected ≥2 round lines on stderr; got \(lines.count): \(r.stderr)")
        // Each stderr line is a JSON object with a `round` field
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let obj = try JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any]
            #expect(obj?["round"] != nil, "stderr line missing 'round' field: \(line)")
            #expect(obj?["codingPath"] != nil)
            #expect(obj?["removedKeys"] != nil)
        }
    }

    // MARK: - --all flag (validate-mode iterator)

    @Test("--all surfaces every fixable diagnosis on stderr, ending in ok")
    func allFlagMultiStray() throws {
        let path = try Self.fixturePath("multi-stray.yaml")
        let r = try Self.runCLI(["--all", path])
        #expect(r.exitCode == 0)
        // stdout has the final summary
        let summary = try Self.parseJSON(r.stdout)
        #expect(summary["status"] as? String == "ok")
        let found = (summary["diagnosesFound"] as? Int) ?? 0
        let fixable = (summary["fixableDiagnoses"] as? Int) ?? 0
        #expect(found >= 3, "expected at least 3 diagnoses (2 violations + 1 terminal ok); got \(found)")
        #expect(fixable >= 2)
        // stderr has per-diagnosis JSON lines with `index` field
        let lines = r.stderr.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(lines.count == found, "expected \(found) stderr lines, got \(lines.count)")
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            #expect(obj?["index"] != nil)
        }
    }

    @Test("--all on a clean spec finds one diagnosis (ok) and exits 0")
    func allFlagClean() throws {
        let path = try Self.fixturePath("clean.yaml")
        let r = try Self.runCLI(["--all", path])
        #expect(r.exitCode == 0)
        let summary = try Self.parseJSON(r.stdout)
        #expect(summary["diagnosesFound"] as? Int == 1)
        #expect(summary["fixableDiagnoses"] as? Int == 0)
        #expect(summary["status"] as? String == "ok")
    }

    @Test("--fix and --all together are rejected with exit 2")
    func mutuallyExclusiveFlags() throws {
        let path = try Self.fixturePath("clean.yaml")
        let r = try Self.runCLI(["--fix", "--all", path])
        #expect(r.exitCode == 2)
        #expect(r.stderr.contains("mutually exclusive"))
    }

    // MARK: - Helpers

    struct CLIResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func runCLI(_ args: [String]) throws -> CLIResult {
        let process = Process()
        // Use the built binary directly to avoid `swift run` overhead +
        // any "Build complete!" stderr from SPM rebuild checks.
        process.executableURL = URL(fileURLWithPath: try Self.binaryPath())
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
        )
    }

    /// Locate the `openapi-doctor` binary produced by `swift build`. SPM
    /// puts it under `.build/<config>/openapi-doctor`. We prefer debug
    /// (matches `swift test`) but fall back to release.
    static func binaryPath() throws -> String {
        // The test bundle's executableURL is somewhere under .build/<config>/...
        // Walk up to .build, then find the openapi-doctor binary in the same config.
        let bundleURL = Bundle.module.bundleURL
        var dir = bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("openapi-doctor")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
            dir = dir.deletingLastPathComponent()
        }
        throw CLIError.binaryNotFound
    }

    static func fixturePath(_ name: String) throws -> String {
        let resourceName = (name as NSString).deletingPathExtension
        let resourceExt = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExt,
            subdirectory: "Fixtures",
        ) else {
            throw CLIError.fixtureMissing(name)
        }
        return url.path
    }

    static func copyFixtureToTemp(_ name: String) throws -> String {
        let source = try fixturePath(name)
        let dest = NSTemporaryDirectory() + UUID().uuidString + "-" + name
        try FileManager.default.copyItem(atPath: source, toPath: dest)
        return dest
    }

    static func parseJSON(_ s: String) throws -> [String: Any] {
        // Last non-empty line is the JSON (some envs may prepend build noise).
        let lines = s.split(separator: "\n").map(String.init)
        guard let line = lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw CLIError.noOutput
        }
        let data = Data(line.utf8)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj ?? [:]
    }

    enum CLIError: Error {
        case binaryNotFound
        case fixtureMissing(String)
        case noOutput
    }
}
