public extension OpenAPIDoctor.Report.Finding {
    /// A problem makes the document wrong; a suggestion does not.
    enum Severity: Sendable, Hashable {
        case problem
        case suggestion
    }
}
