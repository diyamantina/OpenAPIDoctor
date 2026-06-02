// DegenerateSpecsTests
//
// End-to-end coverage for the two new repair categories introduced
// alongside `vendor-extension-prefix`:
//
//   * `missing-servers` -- inject default `servers: [{url: "/"}]`
//   * `missing-operation-id` -- synthesise stable camelCase ids via
//     the two-pass collision-resolution algorithm
//
// Tests exercise the validator (detection), the repairer (mutation
// round-trip), and idempotence (re-running `--fix` on a repaired
// spec produces zero new rounds).

import Foundation
@testable import OpenAPIDoctor
import Testing

@Suite("Degenerate specs: missing-servers + missing-operationId")
struct DegenerateSpecsTests {
    // MARK: - missing-servers

    @Test("Validator surfaces missing-servers as a fixable diagnosis")
    func validatorDetectsMissingServers() throws {
        let yaml = try ValidatorTests.fixture("no-servers.yaml")
        let diagnosis = OpenAPIDoctor.Validation.Validator().validate(yaml: yaml)
        #expect(!diagnosis.isClean)
        #expect(diagnosis.isAutoRepairable)
        if case .missingServers = diagnosis.kind {
            // ok
        } else {
            Issue.record("expected .missingServers, got \(diagnosis.kind)")
        }
    }

    @Test("Repairer injects default servers and the spec becomes clean")
    func repairerInjectsServers() async throws {
        let yaml = try ValidatorTests.fixture("no-servers.yaml")
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(result.rounds[0].kind == .injectServers)
        #expect(result.rounds[0].injectedDefaultServers == true)
        // Re-validate the round-tripped YAML
        let post = OpenAPIDoctor.Validation.Validator().validate(yaml: repaired)
        #expect(post.isClean)
        // Repaired YAML carries an explicit servers block
        #expect(repaired.contains("servers:"))
        #expect(repaired.contains("Default server (injected by OpenAPIDoctor)"))
    }

    @Test("Re-running --fix on a servers-repaired spec is a no-op (idempotence)")
    func injectServersIdempotent() async throws {
        let yaml = try ValidatorTests.fixture("no-servers.yaml")
        let (firstPass, _) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        let (_, secondPass) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: firstPass)
        #expect(secondPass.rounds.isEmpty)
        #expect(secondPass.isClean)
    }

    // MARK: - missing-operation-id

    @Test("Validator surfaces missing-operation-id with synthesised name in payload")
    func validatorDetectsMissingOpId() throws {
        let yaml = try ValidatorTests.fixture("missing-operation-id.yaml")
        let diagnosis = OpenAPIDoctor.Validation.Validator().validate(yaml: yaml)
        #expect(!diagnosis.isClean)
        #expect(diagnosis.isAutoRepairable)
        guard case let .missingOperationId(path, method, synthesized, collisionIndex) = diagnosis.kind else {
            Issue.record("expected .missingOperationId, got \(diagnosis.kind)")
            return
        }
        #expect(path == "/apod")
        #expect(method == "get")
        #expect(synthesized == "getApod")
        #expect(collisionIndex == 1)
    }

    @Test("Repairer synthesises operationId on a missing-op spec")
    func repairerInjectsOpId() async throws {
        let yaml = try ValidatorTests.fixture("missing-operation-id.yaml")
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(result.rounds[0].kind == .synthesizeOperationId)
        #expect(result.rounds[0].synthesizedOperationId == "getApod")
        #expect(result.rounds[0].opPath == "/apod")
        #expect(result.rounds[0].opMethod == "get")
        // The repaired YAML carries the synthesised id
        #expect(repaired.contains("operationId: getApod"))
        // Re-validate
        let post = OpenAPIDoctor.Validation.Validator().validate(yaml: repaired)
        #expect(post.isClean)
    }

    @Test("Two missing ops with same desired name: first gets natural, second gets _2 suffix")
    func repairerCollisionGetsSuffix() async throws {
        let yaml = try ValidatorTests.fixture("missing-operation-id-collision.yaml")
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 2)
        // The two synthesised names: first the natural, second with _2
        let ids = result.rounds.compactMap(\.synthesizedOperationId)
        #expect(ids == ["getItemsByItemId", "getItemsByItemId_2"])
        let collisionIndices = result.rounds.compactMap(\.collisionIndex)
        #expect(collisionIndices == [1, 2])
        // Both appear in the repaired YAML
        #expect(repaired.contains("operationId: getItemsByItemId"))
        #expect(repaired.contains("operationId: getItemsByItemId_2"))
    }

    @Test("Declared operationId is honoured; missing op with different natural name uses it directly")
    func declaredHonouredNoSuffixWhenNoCollision() async {
        // Inline fixture: `getUsers` declared on `/users` GET; missing
        // op `/users/{id}` GET should synthesise `getUsersById` (no _2,
        // because there's no real collision).
        let yaml = """
        openapi: 3.1.0
        servers:
          - url: http://localhost:8080
        info:
          title: T
          version: 1.0.0
        paths:
          /users:
            get:
              operationId: getUsers
              responses:
                '200': {description: ok}
          /users/{id}:
            get:
              responses:
                '200': {description: ok}
        """
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(result.rounds[0].synthesizedOperationId == "getUsersById")
        #expect(result.rounds[0].collisionIndex == 1)
        #expect(repaired.contains("operationId: getUsersById"))
    }

    @Test("Declared name DOES block a missing op with the same natural name")
    func declaredBlocksMatchingNaturalName() async {
        // `getUsers` already declared on `/a`; missing op `/users` GET
        // would naturally synthesise `getUsers`, so collision → `_2`.
        let yaml = """
        openapi: 3.1.0
        servers:
          - url: http://localhost:8080
        info:
          title: T
          version: 1.0.0
        paths:
          /a:
            get:
              operationId: getUsers
              responses:
                '200': {description: ok}
          /users:
            get:
              responses:
                '200': {description: ok}
        """
        let (_, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        #expect(result.rounds.count == 1)
        #expect(result.rounds[0].synthesizedOperationId == "getUsers_2")
        #expect(result.rounds[0].collisionIndex == 2)
    }

    @Test("Re-running --fix on a repaired missing-op spec is a no-op (idempotence)")
    func injectOpIdIdempotent() async throws {
        let yaml = try ValidatorTests.fixture("missing-operation-id-collision.yaml")
        let (firstPass, _) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        let (_, secondPass) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: firstPass)
        #expect(secondPass.rounds.isEmpty)
        #expect(secondPass.isClean)
    }

    // MARK: - combined fixes

    @Test("Spec missing BOTH servers and operationIds: both repaired in sequence")
    func repairBothDegeneracies() async throws {
        let yaml = try ValidatorTests.fixture("degenerate-both.yaml")
        let (repaired, result) = await OpenAPIDoctor.Repair.Repairer().repair(yaml: yaml)
        #expect(result.isClean)
        // Expect 3 rounds: 1 servers + 2 op-id synthesis
        #expect(result.rounds.count == 3)
        #expect(result.rounds[0].kind == .injectServers)
        // The remaining rounds are synthesise-operationId
        let synthRounds = result.rounds.filter { $0.kind == .synthesizeOperationId }
        #expect(synthRounds.count == 2)
        let synthIds = Set(synthRounds.compactMap(\.synthesizedOperationId))
        #expect(synthIds == ["getUsers", "getUsersById"])
        #expect(repaired.contains("operationId: getUsers"))
        #expect(repaired.contains("operationId: getUsersById"))
        #expect(repaired.contains("Default server (injected by OpenAPIDoctor)"))
    }

    // MARK: - --all dry-run iterator

    @Test("collectAll surfaces missing-servers + missing-op diagnoses then ok")
    func collectAllSurfacesAll() async throws {
        let yaml = try ValidatorTests.fixture("degenerate-both.yaml")
        let diagnoses = await OpenAPIDoctor.Validation.Validator().collectAll(yaml: yaml)
        // 1 missing-servers + 2 missing-op + 1 terminal ok
        #expect(diagnoses.count == 4)
        if case .missingServers = diagnoses[0].kind {
            // ok
        } else {
            Issue.record("first diagnosis should be missingServers, got \(diagnoses[0].kind)")
        }
        if case .missingOperationId = diagnoses[1].kind {
            // ok
        } else {
            Issue.record("second diagnosis should be missingOperationId, got \(diagnoses[1].kind)")
        }
        #expect(diagnoses.last?.isClean == true)
    }

    // MARK: - JSON shape

    @Test("Diagnosis.toJSON for missing-servers carries the expected fields")
    func jsonMissingServers() {
        let d = OpenAPIDoctor.Validation.Diagnosis(kind: .missingServers)
        let json = d.toJSON()
        #expect(json.contains(#""kind":"missing-servers""#))
        #expect(json.contains(#""status":"inconsistency""#))
    }

    @Test("Diagnosis.toJSON for missing-operation-id carries path/method/synthesized/collisionIndex")
    func jsonMissingOpId() throws {
        let d = OpenAPIDoctor.Validation.Diagnosis(kind: .missingOperationId(
            path: "/users/{id}",
            method: "get",
            synthesized: "getUsersById",
            collisionIndex: 2
        ))
        let json = d.toJSON()
        #expect(json.contains(#""kind":"missing-operation-id""#))
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(parsed?["path"] as? String == "/users/{id}")
        #expect(parsed?["method"] as? String == "get")
        #expect(parsed?["synthesized"] as? String == "getUsersById")
        #expect(parsed?["collisionIndex"] as? Int == 2)
    }
}
