// FinjobdumpCorpusTests
//
// Stress test: drive `OpenAPIDoctor.Validation.Validator` over every
// spec.yml in the anonymised `finjobdump/` fixture set. Each of the 22
// service entry-points pulls in shared schemas via cross-folder `$ref`s
// — Stitcher resolves them into one in-memory document, then OpenAPIKit
// validates. The test asserts that every spec ends up `.isClean`, which
// catches regressions in either Stitcher resolution or OpenAPIKit
// decoding.
//
// The corpus is real-world (anonymised) multi-file FinTech specs:
// 594 YAML files across 22 services + 2 shared schema directories.

import Foundation
import Testing

@testable import OpenAPIDoctor

@Suite("Finjobdump corpus: end-to-end")
struct FinjobdumpCorpusTests {

    @Test("Every spec.yml validates cleanly under OpenAPIDoctor")
    func everyServiceValidates() async throws {
        let services = try Self.discoverServices()
        #expect(services.count == 22, "expected 22 service specs; found \(services.count)")

        var failures: [(service: String, diagnosis: String)] = []
        for service in services {
            let validator = OpenAPIDoctor.Validation.Validator()
            let diagnosis = try await validator.validate(at: service.specPath)
            if !diagnosis.isClean {
                failures.append((service.name, diagnosis.description))
            }
        }
        if !failures.isEmpty {
            let lines = failures.map { "  - \($0.service): \($0.diagnosis)" }.joined(separator: "\n")
            Issue.record("\(failures.count) of \(services.count) specs failed:\n\(lines)")
        }
    }

    @Test("Corpus directory contains the expected 594 files")
    func fileCountSanity() throws {
        let dir = try Self.corpusRoot()
        let manager = FileManager.default
        let enumerator = manager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        var count = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                count += 1
            }
        }
        #expect(count == 594, "expected 594 files in the corpus; found \(count)")
    }

    // MARK: - Helpers

    struct Service {
        let name: String
        let specPath: String
    }

    static func corpusRoot() throws -> URL {
        guard let url = Bundle.module.url(
            forResource: "finjobdump",
            withExtension: nil,
            subdirectory: "Fixtures",
        ) else {
            throw CorpusError.bundleMissing
        }
        return url
    }

    static func discoverServices() throws -> [Service] {
        let root = try corpusRoot()
        let manager = FileManager.default
        let entries = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        var services: [Service] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDir else { continue }
            let spec = entry.appendingPathComponent("spec.yml")
            if manager.fileExists(atPath: spec.path) {
                services.append(.init(name: entry.lastPathComponent, specPath: spec.path))
            }
        }
        return services
    }

    enum CorpusError: Error {
        case bundleMissing
    }
}
