// ValidatorTests
//
// End-to-end tests for `OpenAPIDoctor.Validation.Validator`. Each test
// loads a fixture from `Fixtures/`, runs the validator, and asserts
// the structured diagnosis matches expectations.

import Foundation
import Testing

@testable import OpenAPIDoctor

@Suite("Validator: end-to-end")
struct ValidatorTests {

    @Test("Clean spec yields .ok")
    func cleanSpec() async throws {
        let yaml = try Self.fixture("clean.yaml")
        let diagnosis = OpenAPIDoctor.Validation.Validator().validate(yaml: yaml)
        #expect(diagnosis.isClean)
        #expect(diagnosis.kind == .ok)
    }

    @Test("Stray Tag keys yield vendor-extension-prefix")
    func strayTagKeys() async throws {
        let yaml = try Self.fixture("stray-tag-keys.yaml")
        let diagnosis = OpenAPIDoctor.Validation.Validator().validate(yaml: yaml)
        #expect(!diagnosis.isClean)
        #expect(diagnosis.isAutoRepairable)

        guard case let .vendorExtensionPrefix(_, invalidKeys, _) = diagnosis.kind else {
            Issue.record("expected vendorExtensionPrefix, got \(diagnosis.kind)")
            return
        }
        #expect(invalidKeys.sorted() == ["slug", "timezone"])
    }

    @Test("Diagnosis serialises to single-line JSON")
    func jsonShape() throws {
        let diagnosis = OpenAPIDoctor.Validation.Diagnosis(kind: .ok)
        #expect(diagnosis.toJSON() == #"{"status":"ok"}"#)
    }

    /// Load a YAML fixture from the Tests/OpenAPIDoctorTests/Fixtures
    /// bundle. Returns the file's contents as a String.
    static func fixture(_ name: String) throws -> String {
        let resourceName = (name as NSString).deletingPathExtension
        let resourceExt = (name as NSString).pathExtension
        guard let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExt,
            subdirectory: "Fixtures",
        ) else {
            throw FixtureError.missing(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}
