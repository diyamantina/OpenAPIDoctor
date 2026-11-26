public extension OpenAPIDoctor.Report {
    /// Puts findings right by editing lines of the text, so that comments,
    /// order and layout stay. A fix is only offered when examining the edited
    /// text shows that its finding is gone and that nothing was made worse.
    struct Fixer: Sendable {
        private let examiner = Examiner()

        public init() {}

        /// The text with this finding put right; nil when no safe fix is known.
        public func fix(_ finding: Finding, in text: String) -> String? {
            var lines = Lines(text)
            guard Edit.apply(finding, to: &lines), lines.text != text else { return nil }
            let before = examiner.examine(yaml: text)
            let after = examiner.examine(yaml: lines.text)
            let problems = { (list: [Finding]) in list.count { $0.severity == .problem } }
            let same = { (list: [Finding]) in list.count { $0.what == finding.what && $0.place == finding.place } }
            guard same(after) < same(before), after.count < before.count, problems(after) <= problems(before) else { return nil }
            return lines.text
        }

        /// Fixes one finding after another until none that is left can be
        /// fixed; problems before suggestions.
        public func fixAll(_ text: String) -> (text: String, fixed: [Finding]) {
            var current = text
            var fixed: [Finding] = []
            // Each fix removes at least one finding, so this ends.
            while let step = next(in: current) {
                current = step.text
                fixed.append(step.finding)
            }
            return (current, fixed)
        }

        private func next(in text: String) -> (finding: Finding, text: String)? {
            for finding in examiner.examine(yaml: text) {
                if let fixed = fix(finding, in: text) {
                    return (finding, fixed)
                }
            }
            return nil
        }
    }
}
