// Synthesizer
//
// Pre-decode YAML scan that detects two classes of degenerate-but-
// technically-valid OpenAPI 3.x specs that OpenAPIKit will happily
// accept but downstream generators choke on:
//
//   1. Missing document-root `servers:` -- the spec defaults to
//      `[{url: "/"}]` per OpenAPI 3.x §4.7.4, but most consumers
//      expect it to be explicit.
//   2. Operations missing `operationId:` -- recommended but not
//      required per §4.8.10. We synthesise a stable camelCase name
//      from method + path with a two-pass collision-resolution pass.
//
// Lives on `OpenAPIDoctor.Synthesis`. Used by `Validator` (to surface
// the diagnoses in document order) and `Repairer` (to mutate the
// YAML).

import Foundation
import PureYAML

public extension OpenAPIDoctor {
    /// Sub-namespace for YAML-level pre-decode scans that surface
    /// degenerate-spec courtesy diagnoses (missing servers, missing
    /// operationId).
    enum Synthesis {}
}

public extension OpenAPIDoctor.Synthesis {
    /// One operation that needs an operationId synthesised.
    struct MissingOperationId: Sendable, Equatable {
        /// The path-templates key, e.g. `"/users/{id}"`.
        public let path: String

        /// HTTP method in lowercase (`"get"`, `"post"`, …).
        public let method: String

        /// The final resolved operationId -- guaranteed unique in the
        /// document after collision resolution.
        public let synthesized: String

        /// 1 when the natural name was free; >=2 when collision suffix
        /// was applied (`_2`, `_3`, …).
        public let collisionIndex: Int

        public init(path: String, method: String, synthesized: String, collisionIndex: Int) {
            self.path = path
            self.method = method
            self.synthesized = synthesized
            self.collisionIndex = collisionIndex
        }
    }

    /// Aggregate result of one pre-decode scan.
    struct ScanResult: Sendable, Equatable {
        /// `true` when the document root carries no `servers:` key.
        public let missingServers: Bool

        /// Operations missing `operationId`, with the resolved
        /// synthesised name + collision index. Document order.
        public let missingOperationIds: [MissingOperationId]

        public init(missingServers: Bool, missingOperationIds: [MissingOperationId]) {
            self.missingServers = missingServers
            self.missingOperationIds = missingOperationIds
        }

        /// `true` when neither kind of degenerate condition is present.
        public var isClean: Bool {
            !missingServers && missingOperationIds.isEmpty
        }
    }

    /// YAML-level pre-decode scanner. Runs before OpenAPIKit's
    /// strict-decode pass so we can surface conditions that are
    /// technically valid OpenAPI but downstream-hostile.
    struct Scanner: Sendable {
        /// HTTP methods the OpenAPI 3.x spec recognises under a
        /// `Path Item Object` (§4.7.9). Anything else under a path
        /// (`parameters:`, `summary:`, `servers:`, `description:`,
        /// `$ref:`, vendor extensions starting with `x-`) is NOT an
        /// operation and is skipped.
        static let httpMethods: Set<String> = [
            "get", "put", "post", "delete", "options", "head", "patch", "trace",
        ]

        public init() {}

        /// Scan a YAML string for degenerate-spec conditions. Pure:
        /// doesn't touch the filesystem, doesn't mutate anything,
        /// doesn't throw on malformed YAML (returns a clean scan and
        /// lets the strict decoder surface the real error).
        public func scan(yaml: String) -> ScanResult {
            guard
                let root = try? PureYAML.parse(yaml),
                let rootMapping = root.mapping
            else {
                return ScanResult(missingServers: false, missingOperationIds: [])
            }
            let missingServers = (rootMapping["servers"] == nil)
            let missingOps = Self.collectMissingOperationIds(rootMapping: rootMapping)
            return ScanResult(missingServers: missingServers, missingOperationIds: missingOps)
        }

        // MARK: - operationId synthesis (two-pass)

        /// Two-pass synthesis per the issue-comment algorithm:
        ///
        /// Pass 1 -- walk the spec, collect every declared operationId
        /// into `declared`, and every (path, method) missing an id
        /// into `candidates` with its natural desired name.
        ///
        /// Pass 2 -- walk `candidates` in document order, initialising
        /// the running-set with `declared`. For each candidate, take
        /// the desired name if free, else append `_2`, `_3`, … until
        /// free.
        ///
        /// Document order is preserved via PureYAML's ordered
        /// ``PureYAML/Model/Mapping`` (`pairs` is a positional array), the
        /// same guarantee Yams's `Node.Mapping` gave and which a
        /// `[String: Any]` parse would not.
        static func collectMissingOperationIds(rootMapping: PureYAML.Model.Mapping) -> [MissingOperationId] {
            guard let pathsValue = rootMapping["paths"], let paths = pathsValue.mapping else {
                return []
            }
            var declared = Set<String>()
            var candidates: [(path: String, method: String, desired: String)] = []

            // Pass 1: walk paths in document order.
            for pathPair in paths.pairs {
                guard let pathKey = pathPair.keyNode.stringValue else { continue }
                guard let pathItem = pathPair.value.mapping else { continue }
                for methodPair in pathItem.pairs {
                    guard let methodKey = methodPair.keyNode.stringValue else { continue }
                    let method = methodKey.lowercased()
                    guard httpMethods.contains(method) else { continue }
                    guard let operation = methodPair.value.mapping else { continue }
                    if let declaredId = operation["operationId"]?.scalarString, !declaredId.isEmpty {
                        declared.insert(declaredId)
                    } else {
                        let desired = synthesizeName(method: method, path: pathKey)
                        candidates.append((path: pathKey, method: method, desired: desired))
                    }
                }
            }

            // Pass 2: resolve collisions in document order.
            var running = declared
            var resolved: [MissingOperationId] = []
            for candidate in candidates {
                var name = candidate.desired
                var idx = 1
                while running.contains(name) {
                    idx += 1
                    name = "\(candidate.desired)_\(idx)"
                }
                running.insert(name)
                resolved.append(MissingOperationId(
                    path: candidate.path,
                    method: candidate.method,
                    synthesized: name,
                    collisionIndex: idx
                ))
            }
            return resolved
        }

        /// Synthesise the natural (pre-collision) operationId for a
        /// (method, path) pair. Convention: verb + nouns + `By<Param>`
        /// for each path parameter, camelCase throughout.
        ///
        /// Examples:
        ///   - `GET /users`                    → `getUsers`
        ///   - `GET /users/{id}`               → `getUsersById`
        ///   - `POST /accounts/{accountId}/users/{userId}`
        ///                                     → `postAccountsByAccountIdUsersByUserId`
        ///   - `GET /items/{item-id}`          → `getItemsByItemId`
        ///   - `GET /v1/users`                 → `getV1Users`
        ///   - `GET /` or `GET /apod`          → `get` / `getApod`
        ///
        /// Server URL prefixes do NOT participate -- the path-templates
        /// object §4.7.9 lives below `paths:`, not under `servers:`.
        public static func synthesizeName(method: String, path: String) -> String {
            var result = method.lowercased()
            let segments = path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            for segment in segments {
                if segment.hasPrefix("{"), segment.hasSuffix("}"), segment.count >= 2 {
                    let raw = String(segment.dropFirst().dropLast())
                    let camel = camelCaseSegment(raw)
                    let pascal = pascalCaseFromCamel(camel)
                    result += "By" + pascal
                } else {
                    let camel = camelCaseSegment(segment)
                    result += pascalCaseFromCamel(camel)
                }
            }
            return result
        }

        /// Fold a single path segment (already with braces stripped if
        /// it was a param) into camelCase. Splits on `-`, `_`, `.`, ` `
        /// and joins with the first piece lowercased + subsequent
        /// pieces pascal-cased. Pure ASCII; non-ASCII chars pass
        /// through.
        static func camelCaseSegment(_ raw: String) -> String {
            let pieces = raw
                .split(whereSeparator: { "-_. ".contains($0) })
                .map(String.init)
            guard let first = pieces.first else { return "" }
            let head = first.lowercasingFirstAsciiLetter()
            let tail = pieces.dropFirst().map { $0.pascalCasedAscii() }
            return ([head] + tail).joined()
        }

        /// Upper-case the first ASCII letter of a camelCase token so it
        /// becomes the leading word of a Pascal-cased name.
        static func pascalCaseFromCamel(_ camel: String) -> String {
            camel.pascalCasedAscii()
        }
    }
}

// MARK: - String helpers (private to Synthesizer)

private extension String {
    /// Lower-case only the first ASCII letter, leave the rest intact.
    /// Used to fold a path segment into camelCase without disturbing
    /// inner casing (e.g. `"UserId"` → `"userId"`).
    func lowercasingFirstAsciiLetter() -> String {
        guard let first else { return self }
        if first.isASCII, first.isLetter {
            return first.lowercased() + dropFirst()
        }
        return self
    }

    /// Pascal-case: upper-case the first ASCII letter, leave the rest
    /// intact. Pure ASCII to keep synthesised names stable across
    /// locales; non-ASCII chars pass through.
    func pascalCasedAscii() -> String {
        guard let first else { return self }
        if first.isASCII, first.isLetter {
            return first.uppercased() + dropFirst()
        }
        return self
    }
}
