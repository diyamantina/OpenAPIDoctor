// RepairerTests
//
// Exercises `OpenAPIDoctor.Repair.Repairer` end-to-end. Each test loads
// a fixture with known violations, runs the repairer, and asserts the
// expected rounds + final state.

import Foundation
@testable import OpenAPIDoctor
import Testing

@Suite("Repairer: end-to-end")
struct RepairerTests {
    @Test("Clean spec triggers no repair rounds and stays clean")
    func cleanSpecNoOp() async throws {
        let yaml = try ValidatorTests.fixture("clean.yaml")
        let repairer = OpenAPIDoctor.Repair.Repairer()
        let (repaired, result) = await repairer.repair(yaml: yaml)
        #expect(result.rounds.isEmpty)
        #expect(result.isClean)
        // Validator still says ok after the round-trip
        let post = OpenAPIDoctor.Validation.Validator().validate(yaml: repaired)
        #expect(post.isClean)
    }

    @Test("Single stray-tag-keys spec repairs in one round")
    func singleStrayTagKeys() async throws {
        let yaml = try ValidatorTests.fixture("stray-tag-keys.yaml")
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(Set(result.rounds[0].removedKeys) == ["slug", "timezone"])
        // Final spec validates ok
        let post = OpenAPIDoctor.Validation.Validator().validate(yaml: repaired)
        #expect(post.isClean)
    }

    @Test("Stray parameter keys repair in one round")
    func strayParameterKeys() async throws {
        let yaml = try ValidatorTests.fixture("stray-parameter-keys.yaml")
        let (_, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(Set(result.rounds[0].removedKeys) == ["email", "phone"])
    }

    @Test("Multi-stray spec repairs across multiple rounds")
    func multiStray() async throws {
        let yaml = try ValidatorTests.fixture("multi-stray.yaml")
        let (_, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count >= 2) // at least two tag objects to fix
        #expect(result.totalRemovedKeys == 3) // slug + timezone + region
    }

    @Test("Missing required field is NOT auto-fixable and surfaces clearly")
    func missingRequiredNotAutoFixable() async throws {
        let yaml = try ValidatorTests.fixture("missing-required.yaml")
        let (_, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(!result.isClean)
        #expect(result.rounds.isEmpty)
        // The final diagnosis should NOT be vendorExtensionPrefix (since
        // the issue is structural, not a stray-key violation)
        switch result.finalDiagnosis.kind {
        case .vendorExtensionPrefix:
            Issue.record("expected non-fixable diagnosis, got vendorExtensionPrefix")
        default:
            break // ok: anything non-fixable is fine
        }
    }

    @Test("RepairResult.toJSON emits a parseable single-line summary")
    func repairResultJSON() async throws {
        let yaml = try ValidatorTests.fixture("stray-tag-keys.yaml")
        let (_, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        let json = result.toJSON()
        #expect(json.contains(#""status":"repaired""#))
        #expect(json.contains(#""roundsApplied":1"#))
        // Round-trip parseable
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        #expect((parsed as? [String: Any])?["status"] as? String == "repaired")
    }

    @Test("In-place repair never overwrites the source when the result is not clean")
    func inPlaceRepairLeavesSourceUntouchedWhenNotClean() async throws {
        // A spec with a fixable issue (no `servers:` block) layered over a
        // non-fixable one (`in: nowhere` is not a valid parameter location).
        // The repairer injects servers -- a round runs -- but the spec still
        // validates non-clean afterward. In-place repair must NOT write this
        // worse-than-the-user-gave-us state back over their source file.
        let source = """
        openapi: 3.0.3
        info:
          title: Partial Repair Fixture
          version: 1.0.0
        paths:
          /x:
            get:
              operationId: getX
              parameters:
                - name: q
                  in: nowhere
                  schema:
                    type: string
              responses:
                '200':
                  description: ok
        """
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openapi-doctor-fix-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let specURL = dir.appendingPathComponent("spec.yaml")
        try source.write(to: specURL, atomically: true, encoding: .utf8)

        let result = try await OpenAPIDoctor.Repair.Repairer().repair(
            at: specURL.path,
            resolveExternalRefs: false
        )

        // A fix ran, yet the spec is still not clean: exactly the case the
        // guard protects.
        #expect(result.rounds.isEmpty == false)
        #expect(result.isClean == false)

        // The source file is byte-for-byte what the user gave us.
        let afterRepair = try String(contentsOf: specURL, encoding: .utf8)
        #expect(afterRepair == source)
    }
}
