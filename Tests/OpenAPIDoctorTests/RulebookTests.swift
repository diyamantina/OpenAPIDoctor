@testable import OpenAPIDoctor
import Testing

@Suite("The rule a finding breaks, and the fix written as YAML")
struct RulebookTests {
    private static func findings(_ yaml: String) -> [OpenAPIDoctor.Report.Finding] {
        OpenAPIDoctor.Report.Examiner().examine(yaml: yaml)
    }

    private static let faulty = """
    openapi: 3.1.0
    info: { title: Faulty, version: "1" }
    paths:
      /items/{id}:
        get:
          operationId: shared
          parameters:
            - { name: id, in: path, schema: { type: string } }
          responses: { "200": { description: ok } }
      /ping:
        get:
          operationId: shared
          responses:
            "200": { headers: {} }
    components:
      schemas:
        Count: { type: int }
        Name: { type: string, nullable: true }
        Age: { type: integer, minimum: 2, maximum: 1 }
        Both: { type: string, readOnly: true, writeOnly: true }
        Price: { type: number, exclusiveMinimum: true }
    """

    @Test("every finding names a rule, and the faults we know show the fix as YAML")
    func every() {
        let findings = Self.findings(Self.faulty)
        // eight faults and the suggestion about servers
        #expect(findings.count == 9, "\(findings)")
        for finding in findings {
            #expect(!finding.rule.isEmpty, "\(finding.what)")
        }
        #expect(findings.filter { $0.example == nil }.map(\.what) == ["A number is expected here, and this is true or false."])
    }

    @Test("the rule and the example of a path parameter")
    func parameter() throws {
        let finding = try #require(Self.findings(Self.faulty).first)
        #expect(finding.rule == "OpenAPI, Parameter Object: when `in` is `path`, `required` must be present and `true`.")
        #expect(finding.example == "- name: id\n  in: path\n  required: true")
    }

    @Test("what the specification allows is not called its rule")
    func bounds() throws {
        let finding = try #require(Self.findings(Self.faulty).first { $0.what.hasPrefix("`minimum`") })
        #expect(finding.rule.hasPrefix("Not forbidden by the specification"))
    }
}
