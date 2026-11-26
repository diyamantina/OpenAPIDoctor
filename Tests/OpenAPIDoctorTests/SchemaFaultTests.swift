@testable import OpenAPIDoctor
import Testing

/// Faults inside a schema that the typed reading accepts without a word.
@Suite("Schema faults: a nullable keyword in 3.1, and bounds no value can meet")
struct SchemaFaultTests {
    private static let validator = OpenAPIDoctor.Validation.Validator()

    private static func document(_ version: String, schema: String) -> String {
        "openapi: \(version)\ninfo: { title: Schemas, version: \"1\" }\nservers: [{ url: / }]\npaths: {}\ncomponents:\n  schemas:\n    Thing: \(schema)\n"
    }

    @Test("faults, each reported at its place", arguments: [
        ("3.1.0", "{ type: string, nullable: true }", ["components", "schemas", "Thing"]),
        (
            "3.1.0",
            "{ type: object, allOf: [{ type: object, properties: { old: { type: string, nullable: false } } }] }",
            ["components", "schemas", "Thing", "allOf", "0", "properties", "old"]
        ),
        ("3.1.0", "{ type: integer, minimum: 100, maximum: 1 }", ["components", "schemas", "Thing"]),
        ("3.0.3", "{ type: number, minimum: 1.5, maximum: 1 }", ["components", "schemas", "Thing"]),
        ("3.1.0", "{ type: array, items: { type: string }, minItems: 3, maxItems: 2 }", ["components", "schemas", "Thing"]),
        ("3.1.0", "{ type: string, minLength: 3, maxLength: 2 }", ["components", "schemas", "Thing"]),
    ])
    func faults(version: String, schema: String, place: [String]) {
        let diagnosis = Self.validator.validate(yaml: Self.document(version, schema: schema))
        guard case let .inconsistency(codingPath, _, _) = diagnosis.kind else {
            Issue.record("expected an inconsistency, got \(diagnosis)")
            return
        }
        #expect(codingPath == place)
    }

    @Test("what is not a fault", arguments: [
        ("3.0.3", "{ type: string, nullable: true }"),
        ("3.1.0", "{ type: integer, minimum: 1, maximum: 1 }"),
        // a property that happens to be called nullable
        ("3.1.0", "{ type: object, properties: { nullable: { type: boolean }, minimum: { type: integer }, maximum: { type: integer } } }"),
        // example data and extensions are not schemas
        ("3.1.0", "{ type: object, example: { type: string, nullable: true }, default: { type: integer, minimum: 2, maximum: 1 } }"),
        ("3.1.0", "{ type: object, x-note: { type: string, nullable: true } }"),
        // a property that happens to be called example is still a schema, and this one is sound
        ("3.1.0", "{ type: object, properties: { example: { type: string } } }"),
    ])
    func sound(version: String, schema: String) {
        let diagnosis = Self.validator.validate(yaml: Self.document(version, schema: schema))
        #expect(diagnosis.isClean, "\(diagnosis)")
    }

    @Test("a property called default or example is walked like any other")
    func namedLikeData() {
        let schema = "{ type: object, properties: { default: { type: string, nullable: true } } }"
        #expect(!Self.validator.validate(yaml: Self.document("3.1.0", schema: schema)).isClean)
    }
}
