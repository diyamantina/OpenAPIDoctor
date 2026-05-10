// DiagnosisKind
//
// Categorisation of validation results. Lives on
// `OpenAPIDoctor.Validation`.

extension OpenAPIDoctor.Validation {

    /// What kind of result the doctor reached after parsing a spec.
    ///
    /// `ok` means the spec parsed cleanly. Every other case carries an
    /// associated payload describing the failure precisely enough that
    /// a caller can either auto-repair (when `isAutoRepairable` is
    /// `true`) or surface the diagnosis to a human for editing.
    public enum DiagnosisKind: Sendable, Equatable {

        /// Spec parsed without error. No repair needed.
        case ok

        /// A `VendorExtendable` object carried keys that aren't in the
        /// type's documented set and don't start with `x-`. Auto-
        /// repairable by stripping the listed keys at the given
        /// codingPath.
        ///
        /// - Parameters:
        ///   - codingPath: Document-relative coding path to the offending
        ///     object. OpenAPIKit's coding-path segments use `Index N`
        ///     for array positions; literal strings otherwise.
        ///   - invalidKeys: The exact key names that need to be removed.
        ///   - subjectName: Human-readable subject of the violation (the
        ///     OpenAPI object kind, e.g. `Parameter` or `Tag`).
        case vendorExtensionPrefix(codingPath: [String], invalidKeys: [String], subjectName: String)

        /// Another `InconsistencyError` from OpenAPIKit that isn't a
        /// vendor-extension-prefix violation. Includes the full
        /// human-readable details from the parser.
        case inconsistency(codingPath: [String], details: String, subjectName: String)

        /// Standard `DecodingError` from Foundation that isn't an
        /// OpenAPIKit-wrapped inconsistency. Catches type mismatches,
        /// missing required keys, and malformed values that need human
        /// attention.
        case decodingError(codingPath: [String], details: String)

        /// The spec file couldn't be read from disk (missing, unreadable,
        /// permissions).
        case fileError(details: String)

        /// Any other error not categorised above. Includes the
        /// `String(describing:)` for surfacing.
        case unknown(details: String)

        /// `true` when the orchestrator can fix this diagnosis without
        /// human intervention.
        public var isAutoRepairable: Bool {
            switch self {
            case .vendorExtensionPrefix:
                return true
            case .ok, .inconsistency, .decodingError, .fileError, .unknown:
                return false
            }
        }
    }
}
