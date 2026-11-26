@testable import OpenAPIDoctor
import Testing

/// A document without `servers:` is valid. It is worth saying, but never instead of a fault that makes the document invalid.
@Suite("A real fault is reported before the advice about servers and operation ids")
struct FaultBeforeAdviceTests {
    private static let validator = OpenAPIDoctor.Validation.Validator()

    @Test("a document with a fault and no servers reports the fault", arguments: [
        // no info
        "openapi: 3.0.3\npaths: {}\n",
        // a path parameter that is not required
        """
        openapi: 3.0.3
        info: { title: Faulty, version: "1" }
        paths:
          /items/{id}:
            get:
              parameters: [{ name: id, in: path, schema: { type: string } }]
              responses: { "200": { description: ok } }
        """,
        // one operation id used twice
        """
        openapi: 3.0.3
        info: { title: Twice, version: "1" }
        paths:
          /a:
            get: { operationId: shared, responses: { "200": { description: ok } } }
          /b:
            get: { operationId: shared, responses: { "200": { description: ok } } }
        """,
    ])
    func faultFirst(yaml: String) {
        let diagnosis = Self.validator.validate(yaml: yaml)
        #expect(!diagnosis.isClean)
        #expect(!diagnosis.isAutoRepairable, "\(diagnosis)")
        #expect(diagnosis.kind != .missingServers)
    }

    @Test("an operation id used twice is an inconsistency that says what failed, not an unknown error")
    func sameIdTwice() {
        let yaml = """
        openapi: 3.1.0
        info: { title: Twice, version: "1" }
        servers: [{ url: / }]
        paths:
          /a:
            get: { operationId: shared, responses: { "200": { description: ok } } }
          /b:
            get: { operationId: shared, responses: { "200": { description: ok } } }
        """
        guard case let .inconsistency(_, details, _) = Self.validator.validate(yaml: yaml).kind else {
            Issue.record("expected an inconsistency")
            return
        }
        #expect(details.contains("Operation Ids"))
    }

    @Test("a valid document without servers still says so")
    func adviceStays() {
        let yaml = "openapi: 3.1.0\ninfo: { title: Plain, version: \"1\" }\npaths: {}\n"
        #expect(Self.validator.validate(yaml: yaml).kind == .missingServers)
    }
}
