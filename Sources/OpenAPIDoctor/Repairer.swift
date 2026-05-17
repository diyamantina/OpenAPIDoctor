// Repairer
//
// Applies mechanical fixes to a YAML spec in a validate → fix → revalidate
// loop, stopping when the spec is clean or when the next diagnosis isn't
// auto-repairable. Lives on `OpenAPIDoctor.Repair`.

import Foundation
import Yams

extension OpenAPIDoctor.Repair {

    /// Repairs auto-fixable spec violations by stripping the offending
    /// keys at the coding path the validator reports, then re-running
    /// validation. Continues until the spec is clean, the next
    /// diagnosis is non-fixable, or `maxRounds` is reached.
    ///
    /// Currently fixes only the `vendorExtensionPrefix` class of
    /// diagnoses. Other kinds (inconsistency, decodingError) need
    /// human attention and stop the loop.
    public struct Repairer: Sendable {

        public init() {}

        /// Repair an already-loaded YAML string. Returns the repaired
        /// YAML alongside the per-round audit trail. Pure: doesn't
        /// touch the filesystem.
        ///
        /// - Parameters:
        ///   - yaml: Spec contents.
        ///   - maxRounds: Loop ceiling; defaults to 30.
        ///   - onRound: Optional callback invoked once per round as the
        ///     repair progresses. Useful for streaming progress to a
        ///     CLI or a log. Fired after each successful strip; not
        ///     fired for the final no-op round when validation comes
        ///     back clean.
        public func repair(
            yaml: String,
            maxRounds: Int = 30,
            onRound: ((OpenAPIDoctor.Repair.RepairRound) -> Void)? = nil,
        ) async -> (repaired: String, result: OpenAPIDoctor.Repair.RepairResult) {
            var current = yaml
            var rounds: [OpenAPIDoctor.Repair.RepairRound] = []
            let validator = OpenAPIDoctor.Validation.Validator()

            for _ in 0..<maxRounds {
                let diagnosis = validator.validate(yaml: current)
                if case .ok = diagnosis.kind {
                    return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                }
                switch diagnosis.kind {
                case let .vendorExtensionPrefix(codingPath, invalidKeys, _) where !invalidKeys.isEmpty:
                    guard let stripped = try? Self.stripKeys(yaml: current, codingPath: codingPath, keys: invalidKeys) else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    current = stripped
                    let round = OpenAPIDoctor.Repair.RepairRound(
                        kind: .stripVendorKeys,
                        codingPath: codingPath,
                        removedKeys: invalidKeys,
                    )
                    rounds.append(round)
                    onRound?(round)
                case .missingServers:
                    guard let patched = try? Self.injectDefaultServers(yaml: current) else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    current = patched
                    let round = OpenAPIDoctor.Repair.RepairRound(
                        kind: .injectServers,
                        codingPath: [],
                        injectedDefaultServers: true,
                    )
                    rounds.append(round)
                    onRound?(round)
                case .missingOperationId:
                    // Apply ALL missing-id fixes in one round — the
                    // two-pass synthesis has already resolved every
                    // collision deterministically and per-op rounds
                    // would scale quadratically on large specs.
                    let scan = OpenAPIDoctor.Synthesis.Scanner().scan(yaml: current)
                    guard !scan.missingOperationIds.isEmpty else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    guard let patched = try? Self.injectOperationIds(
                        yaml: current,
                        ids: scan.missingOperationIds,
                    ) else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    current = patched
                    for op in scan.missingOperationIds {
                        let round = OpenAPIDoctor.Repair.RepairRound(
                            kind: .synthesizeOperationId,
                            codingPath: ["paths", op.path, op.method],
                            synthesizedOperationId: op.synthesized,
                            collisionIndex: op.collisionIndex,
                            opPath: op.path,
                            opMethod: op.method,
                        )
                        rounds.append(round)
                        onRound?(round)
                    }
                default:
                    return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                }
            }

            let finalDiagnosis = validator.validate(yaml: current)
            return (current, .init(rounds: rounds, finalDiagnosis: finalDiagnosis))
        }

        /// Repair a spec at a file path. Writes the repaired YAML back
        /// in place when `writeInPlace` is `true` (default).
        ///
        /// Multi-file specs are loaded through Stitcher first (so
        /// external `$ref`s are merged), but the resulting stitched
        /// YAML is what gets written back — callers who want to
        /// preserve the multi-file layout should pass
        /// `writeInPlace: false` and write the result themselves.
        ///
        /// - Parameters:
        ///   - path: Filesystem path to the spec.
        ///   - maxRounds: Loop ceiling; defaults to 30.
        ///   - writeInPlace: When `true` (default) and any round
        ///     ran, the repaired YAML is written back to `path`.
        ///   - resolveExternalRefs: When `true` (default), Stitcher
        ///     resolves cross-file `$ref`s before repair. Pass
        ///     `false` to repair a single file without following
        ///     external refs.
        @discardableResult
        public func repair(
            at path: String,
            maxRounds: Int = 30,
            writeInPlace: Bool = true,
            resolveExternalRefs: Bool = true,
            onRound: ((OpenAPIDoctor.Repair.RepairRound) -> Void)? = nil,
        ) async throws -> OpenAPIDoctor.Repair.RepairResult {
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let yaml = try await loader.load(from: path, resolveExternalRefs: resolveExternalRefs)
            let (repaired, result) = await repair(yaml: yaml, maxRounds: maxRounds, onRound: onRound)
            if writeInPlace, result.rounds.isEmpty == false {
                try repaired.write(toFile: path, atomically: true, encoding: .utf8)
            }
            return result
        }

        // MARK: - YAML mutation

        /// Walk the YAML to `codingPath`, delete `keys` from the object
        /// there, return the re-serialised YAML.
        ///
        /// OpenAPIKit's coding-path segments use `Index N` for array
        /// positions; everything else is a literal string key.
        static func stripKeys(
            yaml: String,
            codingPath: [String],
            keys: [String],
        ) throws -> String {
            var root = try Yams.load(yaml: yaml)
            guard root != nil else {
                throw RepairError.notADocument
            }
            root = try walk(node: root, codingPath: codingPath, depth: 0, mutate: { node in
                guard var dict = node as? [String: Any] else {
                    throw RepairError.targetNotADictionary(codingPath)
                }
                for key in keys {
                    dict.removeValue(forKey: key)
                }
                return dict
            })
            // Re-encode. Yams.dump preserves enough of the structure for
            // our auto-repair use case (the spec is regenerated on every
            // round anyway). Stable key ordering isn't guaranteed.
            return try Yams.dump(object: root)
        }

        /// Recursive walker that descends into the YAML tree by
        /// `codingPath`, applies `mutate` at the leaf, and rebuilds
        /// the tree from the bottom up.
        static func walk(
            node: Any?,
            codingPath: [String],
            depth: Int,
            mutate: (Any?) throws -> Any?,
        ) throws -> Any? {
            if depth == codingPath.count {
                return try mutate(node)
            }
            let segment = codingPath[depth]
            if let indexMatch = parseIndex(segment) {
                guard var array = node as? [Any], indexMatch < array.count else {
                    throw RepairError.targetIndexOutOfRange(codingPath, indexMatch)
                }
                array[indexMatch] = try walk(
                    node: array[indexMatch],
                    codingPath: codingPath,
                    depth: depth + 1,
                    mutate: mutate,
                ) ?? array[indexMatch]
                return array
            }
            guard var dict = node as? [String: Any] else {
                throw RepairError.targetNotADictionary(Array(codingPath.prefix(depth)))
            }
            guard let child = dict[segment] else {
                throw RepairError.keyMissing(Array(codingPath.prefix(depth)), segment)
            }
            dict[segment] = try walk(
                node: child,
                codingPath: codingPath,
                depth: depth + 1,
                mutate: mutate,
            )
            return dict
        }

        /// Parse an OpenAPIKit-style array index segment like `Index 2`
        /// into an `Int`. Returns `nil` for plain key segments.
        static func parseIndex(_ segment: String) -> Int? {
            guard segment.hasPrefix("Index ") else { return nil }
            return Int(segment.dropFirst("Index ".count))
        }

        // MARK: - missing-servers / missing-operationId mutations

        /// Inject a default `servers:` block at the document root if
        /// the YAML carries none.
        ///
        /// Shape:
        ///
        /// ```yaml
        /// servers:
        ///   - url: /
        ///     description: Default server (injected by OpenAPIDoctor)
        /// ```
        ///
        /// Returns the re-serialised YAML. Throws
        /// ``RepairError/notADocument`` if the root isn't a mapping.
        static func injectDefaultServers(yaml: String) throws -> String {
            guard
                let composed = try Yams.compose(yaml: yaml),
                let mapping = composed.mapping
            else {
                throw RepairError.notADocument
            }
            // Build the default servers node.
            let urlScalar = Node.Scalar("/", Tag(.str), .plain)
            let descScalar = Node.Scalar(
                "Default server (injected by OpenAPIDoctor)",
                Tag(.str),
                .plain,
            )
            let serverEntry = Node.mapping(Node.Mapping(
                [
                    (Node.scalar(Node.Scalar("url", Tag(.str), .plain)),
                     Node.scalar(urlScalar)),
                    (Node.scalar(Node.Scalar("description", Tag(.str), .plain)),
                     Node.scalar(descScalar)),
                ],
                Tag(.map),
                .block,
            ))
            let serversArray = Node.sequence(Node.Sequence([serverEntry], Tag(.seq), .block))

            // Yams.Node.Mapping doesn't expose a direct "insert at
            // beginning" API, so we rebuild the mapping with `servers:`
            // prepended.
            var newPairs: [(Node, Node)] = []
            newPairs.append((Node.scalar(Node.Scalar("servers", Tag(.str), .plain)), serversArray))
            for (k, v) in mapping {
                if k.string == "servers" { continue }  // shouldn't happen but be safe
                newPairs.append((k, v))
            }
            let newMapping = Node.mapping(Node.Mapping(newPairs, mapping.tag, mapping.style))
            return try Yams.serialize(node: newMapping)
        }

        /// Synthesise + inject `operationId:` on every operation under
        /// `paths:` that's missing one. The two-pass synthesis from
        /// ``OpenAPIDoctor/Synthesis/Scanner`` has already resolved
        /// every collision; this helper just writes the resolved names
        /// back into the YAML.
        ///
        /// Idempotent: if an op already carries the synthesised id (or
        /// any id), it's left alone.
        static func injectOperationIds(
            yaml: String,
            ids: [OpenAPIDoctor.Synthesis.MissingOperationId],
        ) throws -> String {
            guard
                let composed = try Yams.compose(yaml: yaml),
                let rootMapping = composed.mapping
            else {
                throw RepairError.notADocument
            }
            guard
                let pathsNode = rootMapping["paths"],
                let pathsMapping = pathsNode.mapping
            else {
                throw RepairError.keyMissing([], "paths")
            }
            // Build a (path -> [method -> synthesizedId]) lookup so we
            // can walk the YAML once.
            var pending: [String: [String: String]] = [:]
            for op in ids {
                pending[op.path, default: [:]][op.method] = op.synthesized
            }

            // Rebuild the paths mapping with the synthesised ids written
            // into each missing op. Preserves document order via the
            // `Node.Mapping` iteration.
            var newPathPairs: [(Node, Node)] = []
            for (pathKeyNode, pathItemNode) in pathsMapping {
                guard
                    let pathKey = pathKeyNode.string,
                    let pathItemMapping = pathItemNode.mapping,
                    let perMethod = pending[pathKey]
                else {
                    newPathPairs.append((pathKeyNode, pathItemNode))
                    continue
                }
                var newMethodPairs: [(Node, Node)] = []
                for (methodKeyNode, opNode) in pathItemMapping {
                    guard
                        let methodKey = methodKeyNode.string,
                        let synthesized = perMethod[methodKey.lowercased()],
                        let opMapping = opNode.mapping,
                        opMapping["operationId"] == nil
                    else {
                        newMethodPairs.append((methodKeyNode, opNode))
                        continue
                    }
                    // Prepend operationId so it appears at the top of
                    // the op block — matches the conventional shape
                    // human authors write.
                    var newOpPairs: [(Node, Node)] = []
                    newOpPairs.append((
                        Node.scalar(Node.Scalar("operationId", Tag(.str), .plain)),
                        Node.scalar(Node.Scalar(synthesized, Tag(.str), .plain)),
                    ))
                    for (k, v) in opMapping {
                        newOpPairs.append((k, v))
                    }
                    let newOp = Node.mapping(Node.Mapping(newOpPairs, opMapping.tag, opMapping.style))
                    newMethodPairs.append((methodKeyNode, newOp))
                }
                let newPathItem = Node.mapping(Node.Mapping(newMethodPairs, pathItemMapping.tag, pathItemMapping.style))
                newPathPairs.append((pathKeyNode, newPathItem))
            }
            let newPaths = Node.mapping(Node.Mapping(newPathPairs, pathsMapping.tag, pathsMapping.style))

            // Rebuild the root mapping with the updated paths.
            var newRootPairs: [(Node, Node)] = []
            for (k, v) in rootMapping {
                if k.string == "paths" {
                    newRootPairs.append((k, newPaths))
                } else {
                    newRootPairs.append((k, v))
                }
            }
            let newRoot = Node.mapping(Node.Mapping(newRootPairs, rootMapping.tag, rootMapping.style))
            return try Yams.serialize(node: newRoot)
        }
    }

    /// Errors thrown during YAML mutation. These shouldn't happen if
    /// the validator and the YAML agree on shape, but they're surfaced
    /// rather than crashing so callers can decide what to do.
    public enum RepairError: Swift.Error, CustomStringConvertible {
        case notADocument
        case targetNotADictionary([String])
        case targetIndexOutOfRange([String], Int)
        case keyMissing([String], String)

        public var description: String {
            switch self {
            case .notADocument:
                return "YAML root is not a document"
            case let .targetNotADictionary(path):
                return "target at \(path.joined(separator: "/")) is not a dictionary"
            case let .targetIndexOutOfRange(path, idx):
                return "index \(idx) out of range at \(path.joined(separator: "/"))"
            case let .keyMissing(path, key):
                return "key '\(key)' missing at \(path.joined(separator: "/"))"
            }
        }
    }
}
