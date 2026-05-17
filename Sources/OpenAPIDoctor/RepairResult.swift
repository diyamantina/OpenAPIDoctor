// RepairResult
//
// Captures everything a repair pass does to a spec. Lives on
// `OpenAPIDoctor.Repair`.

import Foundation

extension OpenAPIDoctor.Repair {

    /// What category of repair a single round performed. Used by
    /// callers + the CLI streaming output to surface the kind of fix
    /// without inspecting every field.
    public enum RepairRoundKind: String, Sendable, Equatable {

        /// Stripped one or more stray top-level keys from a
        /// `VendorExtendable` object that didn't carry an `x-` prefix.
        case stripVendorKeys = "strip-vendor-keys"

        /// Injected a default `servers: [{url: "/"}]` block at the
        /// document root because the spec carried none.
        case injectServers = "inject-servers"

        /// Synthesised an `operationId` on an operation that had none.
        /// The resolved name lives on `synthesizedOperationId`.
        case synthesizeOperationId = "synthesize-operation-id"
    }

    /// One mechanical fix applied during repair. Records exactly what
    /// was changed and where, so callers can audit + surface the
    /// changes to humans.
    public struct RepairRound: Sendable, Equatable {

        /// What category of fix this round performed.
        public let kind: RepairRoundKind

        /// Document-relative coding path to the object that was
        /// modified. Same shape as OpenAPIKit reports
        /// (`["paths", "/customers", "get", "parameters", "Index 2"]`).
        public let codingPath: [String]

        /// Top-level keys deleted from the object at `codingPath`
        /// (when `kind == .stripVendorKeys`). Empty for other kinds.
        public let removedKeys: [String]

        /// `true` when a default `servers:` block was injected at the
        /// document root. `false` for other kinds.
        public let injectedDefaultServers: Bool

        /// The synthesised operationId (when
        /// `kind == .synthesizeOperationId`); `nil` otherwise.
        public let synthesizedOperationId: String?

        /// Collision-suffix index of the synthesised operationId;
        /// 1 when the natural name was free. `nil` when not applicable.
        public let collisionIndex: Int?

        /// The path-templates key (e.g. `"/users/{id}"`) the synthesised
        /// op lives on. `nil` when not applicable.
        public let opPath: String?

        /// The HTTP method (lowercase) the synthesised op uses. `nil`
        /// when not applicable.
        public let opMethod: String?

        /// Memberwise initialiser (general). Use the convenience
        /// initialiser below for individual repair kinds.
        public init(
            kind: RepairRoundKind,
            codingPath: [String],
            removedKeys: [String] = [],
            injectedDefaultServers: Bool = false,
            synthesizedOperationId: String? = nil,
            collisionIndex: Int? = nil,
            opPath: String? = nil,
            opMethod: String? = nil,
        ) {
            self.kind = kind
            self.codingPath = codingPath
            self.removedKeys = removedKeys
            self.injectedDefaultServers = injectedDefaultServers
            self.synthesizedOperationId = synthesizedOperationId
            self.collisionIndex = collisionIndex
            self.opPath = opPath
            self.opMethod = opMethod
        }

        /// Back-compat initialiser for callers that constructed a
        /// `RepairRound` directly. Treats the call as a vendor-keys
        /// strip — the only repair kind that existed before 1.1.
        public init(codingPath: [String], removedKeys: [String]) {
            self.init(
                kind: .stripVendorKeys,
                codingPath: codingPath,
                removedKeys: removedKeys,
            )
        }
    }

    /// Aggregate result of a repair pass.
    ///
    /// `rounds` lists each fix in order. `finalDiagnosis` is the result
    /// of the last validation attempt — either ``Validation/DiagnosisKind/ok``
    /// when the spec is now clean, or a non-fixable kind when repair
    /// stopped short of full success.
    public struct RepairResult: Sendable, Equatable {

        public let rounds: [RepairRound]
        public let finalDiagnosis: OpenAPIDoctor.Validation.Diagnosis

        /// Memberwise initialiser.
        public init(
            rounds: [RepairRound],
            finalDiagnosis: OpenAPIDoctor.Validation.Diagnosis,
        ) {
            self.rounds = rounds
            self.finalDiagnosis = finalDiagnosis
        }

        /// Total count of keys removed across all rounds.
        public var totalRemovedKeys: Int {
            rounds.reduce(0) { $0 + $1.removedKeys.count }
        }

        /// `true` when the spec parses cleanly after repair.
        public var isClean: Bool {
            finalDiagnosis.isClean
        }
    }
}

extension OpenAPIDoctor.Repair.RepairResult {

    /// Serialise to a single-line JSON string. Same shape as
    /// ``Validation/Diagnosis/toJSON()`` but augmented with the rounds
    /// list and round count.
    public func toJSON() -> String {
        let roundsPayload: [[String: Any]] = rounds.map { round in
            var dict: [String: Any] = [
                "kind": round.kind.rawValue,
                "codingPath": round.codingPath,
                "removedKeys": round.removedKeys,
            ]
            if round.injectedDefaultServers {
                dict["injectedDefaultServers"] = true
            }
            if let id = round.synthesizedOperationId {
                dict["synthesizedOperationId"] = id
            }
            if let idx = round.collisionIndex {
                dict["collisionIndex"] = idx
            }
            if let p = round.opPath {
                dict["path"] = p
            }
            if let m = round.opMethod {
                dict["method"] = m
            }
            return dict
        }
        let payload: [String: Any] = [
            "status": isClean ? "repaired" : "incomplete",
            "roundsApplied": rounds.count,
            "totalRemovedKeys": totalRemovedKeys,
            "rounds": roundsPayload,
            "finalDiagnosis": finalDiagnosis.kind == .ok ? "ok" : finalDiagnosis.description,
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let str = String(data: data, encoding: .utf8)
        else {
            return #"{"status":"unknown_error","details":"failed to serialise repair result"}"#
        }
        return str
    }
}
