// OpenAPIDoctor.Report
//
// The list of what is wrong with a document, for a person who will fix it.

public extension OpenAPIDoctor {
    /// What is wrong with a document and how to put it right: ``Examiner``
    /// makes the findings, and ``page(_:file:)`` writes them as plain text.
    enum Report {
        /// The findings as a page of plain text: the counts, then each finding
        /// with its line, its place, the fault and the fix. Plain and ordered,
        /// so that it reads well aloud.
        public static func page(_ findings: [Finding], file: String) -> String {
            guard !findings.isEmpty else { return "\(file): nothing to fix\n" }
            let problems = findings.filter { $0.severity == .problem }
            let suggestions = findings.filter { $0.severity == .suggestion }
            var lines = ["\(file): \(heading(problems: problems.count, suggestions: suggestions.count))", ""]
            for (index, finding) in problems.enumerated() {
                lines += block("Problem \(index + 1)", "Wrong:", finding)
            }
            for (index, finding) in suggestions.enumerated() {
                lines += block("Suggestion \(index + 1)", "Note: ", finding)
            }
            return lines.joined(separator: "\n")
        }

        /// The counts in words, as the head of a list.
        public static func heading(problems: Int, suggestions: Int) -> String {
            var parts: [String] = []
            if problems > 0 {
                parts.append("\(problems) \(problems == 1 ? "problem" : "problems") to fix")
            }
            if suggestions > 0 {
                parts.append("\(suggestions) \(suggestions == 1 ? "suggestion" : "suggestions")")
            }
            return parts.isEmpty ? "nothing to fix" : parts.joined(separator: ", ")
        }

        private static func block(_ title: String, _ label: String, _ finding: Finding) -> [String] {
            let line = finding.line.map { ", line \($0)" } ?? ""
            return [
                title + line,
                "  Where:  \(finding.placeInWords)",
                "  \(label)  \(finding.what)",
                "  Fix:    \(finding.how)",
                "  Rule:   \(finding.rule)",
                "",
            ]
        }
    }
}
