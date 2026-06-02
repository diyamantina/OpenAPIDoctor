// DiagnosisKind
//
// Categorisation of validation results. Lives on
// `OpenAPIDoctor.Validation`.

public extension OpenAPIDoctor.Validation {
    /// What kind of result the doctor reached after parsing a spec.
    ///
    /// `ok` means the spec parsed cleanly. Every other case carries an
    /// associated payload describing the failure precisely enough that
    /// a caller can either auto-repair (when `isAutoRepairable` is
    /// `true`) or surface the diagnosis to a human for editing.
    enum DiagnosisKind: Sendable, Equatable {
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

        /// Document root carries no `servers:` key. Technically valid
        /// per OpenAPI 3.x §4.7.4 (the implicit default is
        /// `[{url: "/"}]`), but downstream generators that need an
        /// explicit base URL fail on this. Auto-repairable by injecting
        /// a default servers array at the document root.
        case missingServers

        /// One operation under `paths:` carries no `operationId:`.
        /// Recommended but not required per §4.8.10; every downstream
        /// generator synthesises a name differently, so OpenAPIDoctor
        /// repairs it once, deterministically.
        ///
        /// - Parameters:
        ///   - path: The path-templates key (e.g. `"/users/{id}"`).
        ///   - method: HTTP method in lowercase (`"get"`, `"post"`, …).
        ///   - synthesized: The resolved operationId after two-pass
        ///     collision resolution. Stable + idempotent: re-running
        ///     `--fix` on a repaired spec produces no new diagnoses.
        ///   - collisionIndex: 1 when the natural name was free; >=2
        ///     when a `_<n>` suffix was applied to dodge a collision
        ///     against a declared id or another synthesised name.
        case missingOperationId(path: String, method: String, synthesized: String, collisionIndex: Int)

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
            case .vendorExtensionPrefix, .missingServers, .missingOperationId:
                true
            case .ok, .inconsistency, .decodingError, .fileError, .unknown:
                false
            }
        }
    }
}
