// Validator
//
// Entry point for spec validation. Lives on `OpenAPIDoctor.Validation`.

import Foundation
import OpenAPIKit
import OpenAPIKit30
import OpenAPIKitCore
import Yams

extension OpenAPIDoctor.Validation {

    /// Validates an OpenAPI 3.x spec by decoding it through OpenAPIKit.
    ///
    /// Both YAML and JSON inputs are accepted; the validator picks the
    /// decoder by file extension or accepts a pre-loaded YAML string
    /// directly. OpenAPIKit's strict-mode validation runs during decode
    /// and any failure is surfaced as a structured ``Diagnosis``.
    ///
    /// One quirk worth knowing: Yams's `YAMLDecoder` wraps every
    /// error thrown during nested decoding inside
    /// `DecodingError.dataCorrupted` with the misleading message
    /// "The given data was not valid YAML." The validator chases the
    /// `Context.underlyingError` chain to find the true error
    /// (typically an OpenAPIKit ``InconsistencyError``) so callers see
    /// the actual problem.
    public struct Validator: Sendable {

        public init() {}

        /// Validate a spec at a file path. JSON or YAML; multi-file
        /// specs auto-resolved via Stitcher.
        public func validate(at path: String) async throws -> Diagnosis {
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let yaml: String
            do {
                yaml = try await loader.load(from: path)
            } catch {
                return Diagnosis(kind: .fileError(details: error.localizedDescription))
            }
            return validate(yaml: yaml)
        }

        /// Validate an already-loaded YAML (or YAML-equivalent JSON)
        /// string. Returns the structured diagnosis; never throws.
        ///
        /// Auto-detects the spec's `openapi` version and dispatches to
        /// either ``OpenAPIKit/OpenAPI/Document`` (3.1) or
        /// ``OpenAPIKit30/OpenAPI/Document`` (3.0). Without this split,
        /// 3.0 specs would fail with "Failed to parse Document Version
        /// 3.0.x as one of OpenAPIKit's supported options" because the
        /// 3.1 Document type only recognises 3.1.x.
        public func validate(yaml: String) -> Diagnosis {
            let data = Data(yaml.utf8)
            let version = Self.detectVersion(in: yaml)
            do {
                switch version {
                case .v30:
                    _ = try YAMLDecoder().decode(OpenAPIKit30.OpenAPI.Document.self, from: data)
                case .v31, .unknown:
                    // Default to 3.1 for unknown — that's the more lenient parser.
                    _ = try YAMLDecoder().decode(OpenAPIKit.OpenAPI.Document.self, from: data)
                }
                return Diagnosis(kind: .ok)
            } catch {
                return Self.makeDiagnosis(from: error)
            }
        }

        /// Detected OpenAPI document version. Used internally to pick a
        /// decoder type.
        enum SpecVersion {
            case v30
            case v31
            case unknown
        }

        /// Scan the raw YAML for the `openapi:` field to decide which
        /// decoder to invoke. We avoid parsing twice by reading just
        /// the version line; a full parse failure on the wrong type
        /// would emit misleading errors.
        static func detectVersion(in yaml: String) -> SpecVersion {
            for line in yaml.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("openapi:") else { continue }
                let valuePart = trimmed.dropFirst("openapi:".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if valuePart.hasPrefix("3.0") { return .v30 }
                if valuePart.hasPrefix("3.1") { return .v31 }
                return .unknown
            }
            return .unknown
        }

        /// Convert any error thrown during decode into a structured
        /// ``Diagnosis``. Walks `DecodingError.underlyingError` chains
        /// to surface OpenAPIKit's wrapped `InconsistencyError`.
        static func makeDiagnosis(from error: any Swift.Error) -> Diagnosis {
            if let openAPI = findOpenAPIError(error) {
                return diagnosisFromOpenAPIError(openAPI)
            }
            if let decoding = error as? DecodingError {
                let context = Self.context(for: decoding)
                let codingPath = (context?.codingPath ?? []).map(\.stringValue)
                let details = context?.debugDescription ?? String(describing: decoding)
                return Diagnosis(kind: .decodingError(codingPath: codingPath, details: details))
            }
            return Diagnosis(kind: .unknown(details: String(describing: error)))
        }

        /// Find an `OpenAPIError`-conforming type anywhere in the error
        /// chain, including wrapped `DecodingError.dataCorrupted`.
        static func findOpenAPIError(_ error: any Swift.Error) -> (any OpenAPIError)? {
            if let openAPI = error as? any OpenAPIError {
                return openAPI
            }
            if let decoding = error as? DecodingError, let context = Self.context(for: decoding),
               let underlying = context.underlyingError {
                return findOpenAPIError(underlying)
            }
            return nil
        }

        /// Build a ``Diagnosis`` from an OpenAPIKit error, classifying
        /// the vendor-extension-prefix case specially so the orchestrator
        /// can auto-repair it.
        static func diagnosisFromOpenAPIError(_ error: any OpenAPIError) -> Diagnosis {
            let codingPath = error.codingPath.map(\.stringValue)
            let details = error.localizedDescription
            let subject = error.subjectName
            let invalidKeys = parseInvalidKeys(from: details)
            let isVendorExtensionPrefix =
                details.contains("vendor extension property")
                && !invalidKeys.isEmpty
            if isVendorExtensionPrefix {
                return Diagnosis(kind: .vendorExtensionPrefix(
                    codingPath: codingPath,
                    invalidKeys: invalidKeys,
                    subjectName: subject,
                ))
            }
            return Diagnosis(kind: .inconsistency(
                codingPath: codingPath,
                details: details,
                subjectName: subject,
            ))
        }

        /// Extract the `[ key1, key2 ]` list from OpenAPIKit's
        /// "Invalid properties: [ ... ]" message.
        static func parseInvalidKeys(from details: String) -> [String] {
            guard let openRange = details.range(of: "Invalid properties: [") else {
                return []
            }
            let after = details[openRange.upperBound...]
            guard let closeRange = after.range(of: "]") else {
                return []
            }
            return after[..<closeRange.lowerBound]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        /// Pull the `DecodingError.Context` out of any case.
        static func context(for decoding: DecodingError) -> DecodingError.Context? {
            switch decoding {
            case let .dataCorrupted(context),
                 let .typeMismatch(_, context),
                 let .valueNotFound(_, context),
                 let .keyNotFound(_, context):
                return context
            @unknown default:
                return nil
            }
        }
    }
}
