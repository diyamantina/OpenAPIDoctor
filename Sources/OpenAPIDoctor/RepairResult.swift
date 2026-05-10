// RepairResult
//
// Captures everything a repair pass does to a spec. Lives on
// `OpenAPIDoctor.Repair`.

import Foundation

extension OpenAPIDoctor.Repair {

    /// One mechanical fix applied during repair. Records exactly what
    /// was stripped from where, so callers can audit + surface the
    /// changes to humans.
    public struct RepairRound: Sendable, Equatable {

        /// Document-relative coding path to the object that was
        /// modified. Same shape as OpenAPIKit reports
        /// (`["paths", "/customers", "get", "parameters", "Index 2"]`).
        public let codingPath: [String]

        /// Top-level keys deleted from the object at `codingPath`.
        public let removedKeys: [String]

        /// Memberwise initialiser.
        public init(codingPath: [String], removedKeys: [String]) {
            self.codingPath = codingPath
            self.removedKeys = removedKeys
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
        let roundsPayload: [[String: Any]] = rounds.map {
            ["codingPath": $0.codingPath, "removedKeys": $0.removedKeys]
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
