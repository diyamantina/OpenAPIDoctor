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
        public func repair(
            yaml: String,
            maxRounds: Int = 30,
        ) async -> (repaired: String, result: OpenAPIDoctor.Repair.RepairResult) {
            var current = yaml
            var rounds: [OpenAPIDoctor.Repair.RepairRound] = []
            let validator = OpenAPIDoctor.Validation.Validator()

            for _ in 0..<maxRounds {
                let diagnosis = validator.validate(yaml: current)
                if case .ok = diagnosis.kind {
                    return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                }
                guard
                    case let .vendorExtensionPrefix(codingPath, invalidKeys, _) = diagnosis.kind,
                    !invalidKeys.isEmpty
                else {
                    return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                }

                guard let stripped = try? Self.stripKeys(yaml: current, codingPath: codingPath, keys: invalidKeys) else {
                    return (current, .init(rounds: rounds, finalDiagnosis: diagnosis))
                }
                current = stripped
                rounds.append(.init(codingPath: codingPath, removedKeys: invalidKeys))
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
        @discardableResult
        public func repair(
            at path: String,
            maxRounds: Int = 30,
            writeInPlace: Bool = true,
        ) async throws -> OpenAPIDoctor.Repair.RepairResult {
            let loader = OpenAPIDoctor.Loading.SpecLoader()
            let yaml = try await loader.load(from: path)
            let (repaired, result) = await repair(yaml: yaml, maxRounds: maxRounds)
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
