// Repairer
//
// Applies mechanical fixes to a YAML spec in a validate → fix → revalidate
// loop, stopping when the spec is clean or when the next diagnosis isn't
// auto-repairable. Lives on `OpenAPIDoctor.Repair`.

import Foundation
import PureYAML

public extension OpenAPIDoctor.Repair {
    /// Repairs auto-fixable spec violations by stripping the offending
    /// keys at the coding path the validator reports, then re-running
    /// validation. Continues until the spec is clean, the next
    /// diagnosis is non-fixable, or `maxRounds` is reached.
    ///
    /// Currently fixes only the `vendorExtensionPrefix` class of
    /// diagnoses. Other kinds (inconsistency, decodingError) need
    /// human attention and stop the loop.
    struct Repairer: Sendable {
        public init() {}

        /// Emit re-serialised YAML with plain (unquoted) scalars wherever
        /// that is unambiguous, matching the shape a human author writes
        /// and the shape Yams produced. PureYAML defaults to fully quoted
        /// scalars, which is valid YAML but needlessly rewrites every line.
        static let emitOptions = PureYAML.Emitting.Options(scalarStyle: .plainWhenSafe)

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
            onRound: ((OpenAPIDoctor.Repair.RepairRound) -> Void)? = nil
        ) async -> (repaired: String, result: OpenAPIDoctor.Repair.RepairResult) {
            var current = yaml
            var rounds: [OpenAPIDoctor.Repair.RepairRound] = []
            let validator = OpenAPIDoctor.Validation.Validator()

            for _ in 0 ..< maxRounds {
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
                        removedKeys: invalidKeys
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
                        injectedDefaultServers: true
                    )
                    rounds.append(round)
                    onRound?(round)
                case .missingOperationId:
                    // Apply ALL missing-id fixes in one round. The
                    // two-pass synthesis has already resolved every
                    // collision deterministically and per-op rounds
                    // would scale quadratically on large specs.
                    let scan = OpenAPIDoctor.Synthesis.Scanner().scan(yaml: current)
                    guard !scan.missingOperationIds.isEmpty else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    guard let patched = try? Self.injectOperationIds(
                        yaml: current,
                        ids: scan.missingOperationIds
                    ) else {
                        return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                    }
                    current = patched
                    for operation in scan.missingOperationIds {
                        let round = OpenAPIDoctor.Repair.RepairRound(
                            kind: .synthesizeOperationId,
                            codingPath: ["paths", operation.path, operation.method],
                            synthesizedOperationId: operation.synthesized,
                            collisionIndex: operation.collisionIndex,
                            opPath: operation.path,
                            opMethod: operation.method
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
        /// YAML is what gets written back. Callers who want to
        /// preserve the multi-file layout should pass
        /// `writeInPlace: false` and write the result themselves.
        ///
        /// - Parameters:
        ///   - path: Filesystem path to the spec.
        ///   - maxRounds: Loop ceiling; defaults to 30.
        ///   - writeInPlace: When `true` (default), the repaired YAML is
        ///     written back to `path` only if a round ran *and* the repair
        ///     produced a clean spec. A repair that ends non-clean -- because a
        ///     deeper, non-fixable issue remains, or a fix could not fully
        ///     resolve the spec -- leaves the source file untouched, so a bad
        ///     repair can never overwrite a usable source with a worse one. To
        ///     capture a best-effort partial result without risking the source,
        ///     pass `writeInPlace: false` and write the returned YAML yourself
        ///     (the CLI's `--output` does this).
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
            onRound: ((OpenAPIDoctor.Repair.RepairRound) -> Void)? = nil
        ) async throws -> OpenAPIDoctor.Repair.RepairResult {
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let yaml = try await loader.load(from: path, resolveExternalRefs: resolveExternalRefs)
            let (repaired, result) = await repair(yaml: yaml, maxRounds: maxRounds, onRound: onRound)
            // Overwrite the source only when the repair actually succeeded.
            // Writing a non-clean result back in place could replace a usable
            // spec with a worse one (a fix that regressed it, or a deeper issue
            // surfaced) -- the source file is the one thing we must not corrupt.
            if writeInPlace, result.rounds.isEmpty == false, result.isClean {
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
            keys: [String]
        ) throws -> String {
            let root = try PureYAML.parse(yaml)
            let mutated = try walk(value: root, codingPath: codingPath, depth: 0, mutate: { value in
                guard case let .mapping(mapping) = value else {
                    throw RepairError.targetNotADictionary(codingPath)
                }
                let remaining = mapping.pairs.filter { pair in
                    guard let key = pair.keyNode.stringValue else { return true }
                    return !keys.contains(key)
                }
                return .mapping(PureYAML.Model.Mapping(remaining))
            })
            // Re-emit. The spec is revalidated (and regenerated) on every
            // round, so a semantic round-trip is all that's required here;
            // original scalar formatting and comments are not preserved.
            return PureYAML.dump(mutated, options: emitOptions)
        }

        /// Recursive walker that descends into the YAML value tree by
        /// `codingPath`, applies `mutate` at the leaf, and rebuilds the
        /// tree from the bottom up. Mapping order is preserved by mutating
        /// pairs positionally rather than going through an unordered
        /// dictionary.
        static func walk(
            value: PureYAML.Model.Value,
            codingPath: [String],
            depth: Int,
            mutate: (PureYAML.Model.Value) throws -> PureYAML.Model.Value
        ) throws -> PureYAML.Model.Value {
            if depth == codingPath.count {
                return try mutate(value)
            }
            let segment = codingPath[depth]
            // Dispatch on the value at this node, not on the textual shape
            // of the segment: a sequence is indexed, a mapping is keyed.
            // Decoders disagree on how they stringify an array index
            // (Foundation/Yams emit `Index 0`, PureYAML emits `0`), so the
            // tree is the reliable signal, not the segment string.
            switch value {
            case var .sequence(array):
                guard let index = parseIndex(segment), index < array.count else {
                    throw RepairError.targetIndexOutOfRange(codingPath, parseIndex(segment) ?? -1)
                }
                array[index] = try walk(
                    value: array[index],
                    codingPath: codingPath,
                    depth: depth + 1,
                    mutate: mutate
                )
                return .sequence(array)
            case let .mapping(mapping):
                guard let childIndex = mapping.pairs.firstIndex(where: { $0.keyNode.stringValue == segment }) else {
                    throw RepairError.keyMissing(Array(codingPath.prefix(depth)), segment)
                }
                var pairs = mapping.pairs
                pairs[childIndex].value = try walk(
                    value: pairs[childIndex].value,
                    codingPath: codingPath,
                    depth: depth + 1,
                    mutate: mutate
                )
                return .mapping(PureYAML.Model.Mapping(pairs))
            default:
                throw RepairError.targetNotADictionary(Array(codingPath.prefix(depth)))
            }
        }

        /// Parse an array-index coding-path segment into an `Int`. Accepts
        /// both a bare integer (`2`, as PureYAML's decoder emits) and the
        /// `Index 2` form Foundation/Yams produced. Returns `nil` for a
        /// segment that is neither, i.e. a plain mapping key.
        static func parseIndex(_ segment: String) -> Int? {
            if let direct = Int(segment) {
                return direct
            }
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
            guard case let .mapping(mapping) = try PureYAML.parse(yaml) else {
                throw RepairError.notADocument
            }
            // Build the default servers node. PureYAML's typed value model
            // makes the string tagging explicit, so no scalar-style plumbing
            // is needed.
            let serverEntry = PureYAML.Model.Value.mapping(PureYAML.Model.Mapping([
                PureYAML.Model.Pair(key: "url", value: .string("/")),
                PureYAML.Model.Pair(
                    key: "description",
                    value: .string("Default server (injected by OpenAPIDoctor)")
                ),
            ]))
            let serversArray = PureYAML.Model.Value.sequence([serverEntry])

            // Rebuild the mapping with `servers:` prepended (an ordered
            // mapping has no "insert at beginning" primitive).
            var newPairs = [PureYAML.Model.Pair(key: "servers", value: serversArray)]
            for pair in mapping.pairs where pair.keyNode.stringValue != "servers" {
                newPairs.append(pair)
            }
            return PureYAML.dump(.mapping(PureYAML.Model.Mapping(newPairs)), options: emitOptions)
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
            ids: [OpenAPIDoctor.Synthesis.MissingOperationId]
        ) throws -> String {
            guard case let .mapping(rootMapping) = try PureYAML.parse(yaml) else {
                throw RepairError.notADocument
            }
            guard
                let pathsValue = rootMapping["paths"],
                let pathsMapping = pathsValue.mapping
            else {
                throw RepairError.keyMissing([], "paths")
            }
            // Build a (path -> [method -> synthesizedId]) lookup so we
            // can walk the YAML once.
            var pending: [String: [String: String]] = [:]
            for operation in ids {
                pending[operation.path, default: [:]][operation.method] = operation.synthesized
            }

            // Rebuild the paths mapping with the synthesised ids written
            // into each missing op. Preserves document order via the
            // ordered `pairs` array.
            var newPathPairs: [PureYAML.Model.Pair] = []
            for pathPair in pathsMapping.pairs {
                guard
                    let pathKey = pathPair.keyNode.stringValue,
                    let pathItemMapping = pathPair.value.mapping,
                    let perMethod = pending[pathKey]
                else {
                    newPathPairs.append(pathPair)
                    continue
                }
                var newMethodPairs: [PureYAML.Model.Pair] = []
                for methodPair in pathItemMapping.pairs {
                    guard
                        let methodKey = methodPair.keyNode.stringValue,
                        let synthesized = perMethod[methodKey.lowercased()],
                        let opMapping = methodPair.value.mapping,
                        opMapping["operationId"] == nil
                    else {
                        newMethodPairs.append(methodPair)
                        continue
                    }
                    // Prepend operationId so it appears at the top of
                    // the op block, matching the conventional shape
                    // human authors write.
                    var newOpPairs = [PureYAML.Model.Pair(key: "operationId", value: .string(synthesized))]
                    newOpPairs.append(contentsOf: opMapping.pairs)
                    newMethodPairs.append(PureYAML.Model.Pair(
                        keyNode: methodPair.keyNode,
                        value: .mapping(PureYAML.Model.Mapping(newOpPairs))
                    ))
                }
                newPathPairs.append(PureYAML.Model.Pair(
                    keyNode: pathPair.keyNode,
                    value: .mapping(PureYAML.Model.Mapping(newMethodPairs))
                ))
            }
            let newPaths = PureYAML.Model.Value.mapping(PureYAML.Model.Mapping(newPathPairs))

            // Rebuild the root mapping with the updated paths.
            var newRootPairs: [PureYAML.Model.Pair] = []
            for pair in rootMapping.pairs {
                if pair.keyNode.stringValue == "paths" {
                    newRootPairs.append(PureYAML.Model.Pair(keyNode: pair.keyNode, value: newPaths))
                } else {
                    newRootPairs.append(pair)
                }
            }
            return PureYAML.dump(.mapping(PureYAML.Model.Mapping(newRootPairs)), options: emitOptions)
        }
    }

    /// Errors thrown during YAML mutation. These shouldn't happen if
    /// the validator and the YAML agree on shape, but they're surfaced
    /// rather than crashing so callers can decide what to do.
    enum RepairError: Swift.Error, CustomStringConvertible {
        case notADocument
        case targetNotADictionary([String])
        case targetIndexOutOfRange([String], Int)
        case keyMissing([String], String)

        public var description: String {
            switch self {
            case .notADocument:
                "YAML root is not a document"
            case let .targetNotADictionary(path):
                "target at \(path.joined(separator: "/")) is not a dictionary"
            case let .targetIndexOutOfRange(path, idx):
                "index \(idx) out of range at \(path.joined(separator: "/"))"
            case let .keyMissing(path, key):
                "key '\(key)' missing at \(path.joined(separator: "/"))"
            }
        }
    }
}
