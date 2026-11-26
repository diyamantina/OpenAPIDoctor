import Foundation
@testable import OpenAPIDoctor
import Testing

/// Fix all over every file of the corpus: a fix never damages a file. Real files are the answer to what a hand-written test does not think of.
@Suite("Fix all over the corpus")
struct FixerCorpusTests {
    private static func files() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let walker = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }.filter { ["yaml", "yml"].contains($0.pathExtension) }.sorted { $0.path < $1.path }
    }

    @Test("no file is damaged: it stays readable, gains no problem, keeps its comments, and a second fix all changes nothing")
    func safe() throws {
        let examiner = OpenAPIDoctor.Report.Examiner()
        let fixer = OpenAPIDoctor.Report.Fixer()
        var counted = 0
        var withFindings = 0
        var fixedCount = 0
        var left: [String: Int] = [:]
        var slowest = (seconds: 0.0, file: "")
        for url in try Self.files() {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("openapi:") else { continue }
            counted += 1
            let before = examiner.examine(yaml: text)
            guard !before.isEmpty else { continue }
            withFindings += 1
            let start = Date()
            let result = fixer.fixAll(text)
            let seconds = Date().timeIntervalSince(start)
            if seconds > slowest.seconds {
                slowest = (seconds, url.lastPathComponent)
            }
            let after = examiner.examine(yaml: result.text)
            let name = url.lastPathComponent
            #expect(!after.contains { $0.what == "The text is not valid YAML here." } || before.contains { $0.what == "The text is not valid YAML here." }, "\(name)")
            #expect(after.count { $0.severity == .problem } <= before.count { $0.severity == .problem }, "\(name): \(after)")
            let comments = { (words: String) in words.components(separatedBy: "\n").count { $0.drop { $0 == " " }.hasPrefix("#") } }
            #expect(comments(result.text) == comments(text), "\(name)")
            #expect(fixer.fixAll(result.text).text == result.text, "\(name)")
            fixedCount += result.fixed.count
            for finding in after {
                // The names between backticks differ from file to file; the kind of the finding is what is counted.
                let kind = finding.what.components(separatedBy: "`").enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element : "…" }.joined(separator: "`")
                left[kind, default: 0] += 1
            }
        }
        print("corpus: \(counted) documents, \(withFindings) with findings, \(fixedCount) fixed, slowest \(String(format: "%.2f", slowest.seconds)) s (\(slowest.file))")
        for (kind, count) in left.sorted(by: { $0.value > $1.value }).prefix(15) {
            print("corpus left: \(count) x \(kind)")
        }
        #expect(counted > 0)
    }
}
