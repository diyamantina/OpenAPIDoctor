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
        /// specs auto-resolved via Stitcher unless `resolveExternalRefs`
        /// is `false`.
        ///
        /// - Parameters:
        ///   - path: Filesystem path to the spec.
        ///   - resolveExternalRefs: When `true` (default), runs Stitcher
        ///     to merge external `$ref` files into one document before
        ///     validating. Pass `false` for single-file validation when
        ///     the referenced files aren't available locally.
        public func validate(
            at path: String,
            resolveExternalRefs: Bool = true,
        ) async throws -> Diagnosis {
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let yaml: String
            do {
                yaml = try await loader.load(from: path, resolveExternalRefs: resolveExternalRefs)
            } catch {
                return Diagnosis(kind: .fileError(details: error.localizedDescription))
            }
            return validate(yaml: yaml)
        }

        /// Iteratively validate a YAML string, surfacing EVERY
        /// fixable-class diagnosis (dry-run: doesn't write back).
        ///
        /// OpenAPIKit's decoder stops at the first error, so a vanilla
        /// `validate(yaml:)` only ever returns one diagnosis even if the
        /// spec has multiple violations. `collectAll` runs the same
        /// validate -> strip -> revalidate loop the `Repairer` uses,
        /// but discards the repaired YAML — collecting every diagnosis
        /// encountered along the way.
        ///
        /// Each diagnosis except the last describes a
        /// `vendor-extension-prefix` violation that the repairer fixed
        /// to continue. The last diagnosis describes whatever stopped
        /// the loop: either `.ok` (all violations were fixable) or a
        /// non-fixable kind that needs human attention.
        ///
        /// - Parameters:
        ///   - yaml: Spec contents.
        ///   - maxRounds: Loop ceiling; defaults to 30.
        ///   - onDiagnosis: Optional callback invoked once per
        ///     diagnosis as collection progresses. Useful for streaming
        ///     output to a CLI.
        /// - Returns: All diagnoses found, including the terminal one.
        public func collectAll(
            yaml: String,
            maxRounds: Int = 30,
            onDiagnosis: ((Diagnosis) -> Void)? = nil,
        ) async -> [Diagnosis] {
            var current = yaml
            var diagnoses: [Diagnosis] = []
            for _ in 0..<maxRounds {
                let diagnosis = validate(yaml: current)
                diagnoses.append(diagnosis)
                onDiagnosis?(diagnosis)
                switch diagnosis.kind {
                case let .vendorExtensionPrefix(codingPath, invalidKeys, _) where !invalidKeys.isEmpty:
                    guard let stripped = try? OpenAPIDoctor.Repair.Repairer.stripKeys(
                        yaml: current,
                        codingPath: codingPath,
                        keys: invalidKeys,
                    ) else {
                        return diagnoses
                    }
                    current = stripped
                case .missingServers:
                    guard let patched = try? OpenAPIDoctor.Repair.Repairer.injectDefaultServers(yaml: current) else {
                        return diagnoses
                    }
                    current = patched
                case let .missingOperationId(path, method, synthesized, _):
                    // Apply just the first missing-op fix this round;
                    // the next iteration's scan will surface the next
                    // missing op so `collectAll` can stream one
                    // diagnosis per fix (matching the contract of the
                    // existing vendor-extension-prefix loop).
                    guard let patched = try? OpenAPIDoctor.Repair.Repairer.injectOperationIds(
                        yaml: current,
                        ids: [OpenAPIDoctor.Synthesis.MissingOperationId(
                            path: path,
                            method: method,
                            synthesized: synthesized,
                            collisionIndex: 1,
                        )],
                    ) else {
                        return diagnoses
                    }
                    current = patched
                default:
                    return diagnoses
                }
            }
            return diagnoses
        }

        /// Validate an already-loaded YAML (or YAML-equivalent JSON)
        /// string. Returns the structured diagnosis; never throws.
        ///
        /// Runs the YAML-level pre-scan first to surface degenerate-
        /// spec conditions (missing `servers:`, missing `operationId`)
        /// that OpenAPIKit treats as valid but downstream generators
        /// reject. If the pre-scan finds any condition, the first one
        /// in document order is returned; the repairer fixes it and the
        /// next round picks up the next condition. Once pre-scan is
        /// clean, the strict decoder runs.
        ///
        /// Auto-detects the spec's `openapi` version and dispatches to
        /// either ``OpenAPIKit/OpenAPI/Document`` (3.1) or
        /// ``OpenAPIKit30/OpenAPI/Document`` (3.0). Without this split,
        /// 3.0 specs would fail with "Failed to parse Document Version
        /// 3.0.x as one of OpenAPIKit's supported options" because the
        /// 3.1 Document type only recognises 3.1.x.
        public func validate(yaml: String) -> Diagnosis {
            // Pre-scan: YAML-level checks for degenerate-spec conditions
            // that OpenAPIKit doesn't surface (because they're valid
            // per the OpenAPI 3.x grammar) but downstream consumers
            // need fixed.
            let scan = OpenAPIDoctor.Synthesis.Scanner().scan(yaml: yaml)
            if scan.missingServers {
                return Diagnosis(kind: .missingServers)
            }
            if let firstOp = scan.missingOperationIds.first {
                return Diagnosis(kind: .missingOperationId(
                    path: firstOp.path,
                    method: firstOp.method,
                    synthesized: firstOp.synthesized,
                    collisionIndex: firstOp.collisionIndex,
                ))
            }

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
