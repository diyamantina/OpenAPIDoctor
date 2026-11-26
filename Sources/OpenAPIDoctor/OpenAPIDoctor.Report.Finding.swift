public extension OpenAPIDoctor.Report {
    /// One thing a person can put right in a document.
    struct Finding: Sendable, Hashable {
        public let severity: Severity
        /// The line of the text, counted from one; nil when it is not known.
        public let line: Int?
        /// The keys and indexes from the top of the document to the place.
        public let place: [String]
        /// What is wrong, in one sentence.
        public let what: String
        /// What to do about it, in one sentence.
        public let how: String

        public init(severity: Severity = .problem, line: Int?, place: [String], what: String, how: String) {
            self.severity = severity
            self.line = line
            self.place = place
            self.what = what
            self.how = how
        }

        /// The place as words; an index is counted from one.
        public var placeInWords: String {
            guard !place.isEmpty else { return "the whole file" }
            return place.map { part in Int(part).map { "item \($0 + 1)" } ?? part }.joined(separator: " > ")
        }
    }
}
