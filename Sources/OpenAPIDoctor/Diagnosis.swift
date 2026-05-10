// Diagnosis
//
// The structured result of one validator pass. Lives on
// `OpenAPIDoctor.Validation`.

import Foundation

extension OpenAPIDoctor.Validation {

    /// One validation result, structured for both programmatic
    /// consumption (`kind`) and human display (`description`).
    ///
    /// Returned by ``Validator/validate(at:)`` and
    /// ``Validator/validate(yaml:)``.
    public struct Diagnosis: Sendable, Equatable, CustomStringConvertible {

        /// What the doctor found.
        public let kind: DiagnosisKind

        /// Memberwise initialiser.
        public init(kind: DiagnosisKind) {
            self.kind = kind
        }

        /// `true` when the spec parsed cleanly.
        public var isClean: Bool {
            kind == .ok
        }

        /// `true` when the orchestrator can repair this diagnosis without
        /// human intervention. Equivalent to ``DiagnosisKind/isAutoRepairable``.
        public var isAutoRepairable: Bool {
            kind.isAutoRepairable
        }

        // MARK: - CustomStringConvertible

        public var description: String {
            switch kind {
            case .ok:
                return "OpenAPIDoctor: spec is OpenAPIKit-clean"
            case let .vendorExtensionPrefix(codingPath, invalidKeys, subjectName):
                let pathStr = codingPath.isEmpty ? "<root>" : codingPath.joined(separator: " / ")
                return "OpenAPIDoctor: \(subjectName) at \(pathStr) carries stray keys: \(invalidKeys)"
            case let .inconsistency(codingPath, details, subjectName):
                let pathStr = codingPath.isEmpty ? "<root>" : codingPath.joined(separator: " / ")
                return "OpenAPIDoctor: \(subjectName) at \(pathStr): \(details)"
            case let .decodingError(codingPath, details):
                let pathStr = codingPath.isEmpty ? "<root>" : codingPath.joined(separator: " / ")
                return "OpenAPIDoctor: decoding error at \(pathStr): \(details)"
            case let .fileError(details):
                return "OpenAPIDoctor: file error: \(details)"
            case let .unknown(details):
                return "OpenAPIDoctor: unknown error: \(details)"
            }
        }
    }
}

extension OpenAPIDoctor.Validation.Diagnosis {

    /// Serialise the diagnosis to a single-line JSON string, the format
    /// the bundled CLI emits and the orchestrator parses.
    ///
    /// Output shape:
    ///
    /// ```json
    /// {"status":"ok"}
    /// {"status":"inconsistency","kind":"vendor-extension-prefix","subject":"...","codingPath":[...],"invalidKeys":[...]}
    /// {"status":"decoding_error","details":"...","codingPath":[...]}
    /// {"status":"file_error","details":"..."}
    /// {"status":"unknown_error","details":"..."}
    /// ```
    public func toJSON() -> String {
        let payload: [String: Any]
        switch kind {
        case .ok:
            payload = ["status": "ok"]
        case let .vendorExtensionPrefix(codingPath, invalidKeys, subjectName):
            payload = [
                "status": "inconsistency",
                "kind": "vendor-extension-prefix",
                "subject": subjectName,
                "codingPath": codingPath,
                "invalidKeys": invalidKeys,
            ]
        case let .inconsistency(codingPath, details, subjectName):
            payload = [
                "status": "inconsistency",
                "kind": "inconsistency",
                "subject": subjectName,
                "codingPath": codingPath,
                "details": details,
            ]
        case let .decodingError(codingPath, details):
            payload = [
                "status": "decoding_error",
                "codingPath": codingPath,
                "details": details,
            ]
        case let .fileError(details):
            payload = ["status": "file_error", "details": details]
        case let .unknown(details):
            payload = ["status": "unknown_error", "details": details]
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let str = String(data: data, encoding: .utf8)
        else {
            return #"{"status":"unknown_error","details":"failed to serialise diagnosis"}"#
        }
        return str
    }
}
