@testable import OpenAPIDoctor
import Testing

@Suite("The examiner: every fault it can find, each with its line, what is wrong and how to fix it")
struct ExaminerTests {
    private typealias Finding = OpenAPIDoctor.Report.Finding

    private static let examiner = OpenAPIDoctor.Report.Examiner()

    /// Six faults in six different places, and no `servers`. The numbers are the lines of the text.
    private static let faulty = """
    openapi: 3.1.0
    info:
      title: Faulty
      version: "1"
    paths:
      /items/{id}:
        get:
          operationId: shared
          parameters:
            - name: id
              in: path
              schema: { type: string }
          responses:
            "200": { description: ok }
      /ping:
        get:
          operationId: shared
          responses:
            "200":
              headers: {}
    components:
      schemas:
        Widget:
          type: object
          properties:
            count:
              type: int
        Price:
          type: number
          exclusiveMinimum: true
        Name:
          type: string
          nullable: true
        Age: { type: integer, minimum: 100, maximum: 1 }
    """

    @Test("every fault is listed once, in the order of the file, and the suggestion comes last")
    func all() {
        let findings = Self.examiner.examine(yaml: Self.faulty)
        let problems = findings.filter { $0.severity == .problem }
        #expect(problems.map(\.line) == [10, 17, 19, 27, 30, 31, 34], "\(findings)")
        #expect(findings.filter { $0.severity == .suggestion }.map(\.what) == ["The file lists no `servers`."])
        #expect(findings.last?.severity == .suggestion)
        for finding in findings {
            #expect(!finding.what.isEmpty && !finding.how.isEmpty, "\(finding)")
            #expect(!finding.what.contains("could not be decoded"), "the parser's own long text is not shown: \(finding.what)")
        }
    }

    @Test("the words for the common faults")
    func words() {
        let problems = Self.examiner.examine(yaml: Self.faulty).filter { $0.severity == .problem }
        #expect(problems.map(\.what) == [
            "The path parameter `id` is not marked as required.",
            "The operationId `shared` is already used on line 8.",
            "`description` is missing.",
            "`int` is not a type.",
            "A number is expected here, and this is true or false.",
            "`nullable` is not a keyword of OpenAPI 3.1 and is ignored.",
            "`minimum` is larger than `maximum`, so no value can meet both.",
        ])
    }

    @Test("a sound file gives nothing")
    func sound() {
        let yaml = """
        openapi: 3.0.3
        info: { title: Sound, version: "1" }
        servers: [{ url: / }]
        paths:
          /a:
            get: { operationId: a, responses: { "200": { description: ok } } }
        """
        #expect(Self.examiner.examine(yaml: yaml).isEmpty)
    }

    @Test("text that is not YAML, a version nobody reads, and a missing info", arguments: [
        ("openapi: 3.1.0\ninfo:\n  version: [1\npaths: {}\n", "The text is not valid YAML here."),
        ("openapi: \"2.0\"\ninfo: { title: A, version: \"1\" }\npaths: {}\n", "OpenAPI version `2.0` is not supported."),
        ("openapi: 3.1.0\nservers: [{ url: / }]\npaths: {}\n", "`info` is missing."),
    ])
    func whole(yaml: String, what: String) {
        #expect(Self.examiner.examine(yaml: yaml).first?.what == what)
    }

    @Test("the page of text: a heading with the counts, then each finding numbered, with its line, place, fault and fix")
    func text() {
        let yaml = "openapi: 3.1.0\ninfo: { title: A, version: \"1\" }\npaths: {}\ncomponents:\n  schemas:\n    Age: { type: integer, minimum: 2, maximum: 1 }\n"
        let page = OpenAPIDoctor.Report.page(Self.examiner.examine(yaml: yaml), file: "a.yaml")
        #expect(page == """
        a.yaml: 1 problem to fix, 1 suggestion

        Problem 1, line 6
          Where:  components > schemas > Age
          Wrong:  `minimum` is larger than `maximum`, so no value can meet both.
          Fix:    Make `minimum` smaller than or equal to `maximum`.
          Rule:   Not forbidden by the specification, but JSON Schema asks a value to meet both bounds, and none can.

        Suggestion 1, line 1
          Where:  the whole file
          Note:   The file lists no `servers`.
          Fix:    Add `servers:` with the address of the service, for example `- url: /`.
          Rule:   OpenAPI Object: `servers` is optional; without it the address is `/`.

        """)
        #expect(OpenAPIDoctor.Report.page([], file: "a.yaml") == "a.yaml: nothing to fix\n")
    }
}
