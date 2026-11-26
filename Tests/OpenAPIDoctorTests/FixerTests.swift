@testable import OpenAPIDoctor
import Testing

@Suite("The fixer: a fix is offered only when the checked text shows that the finding is gone")
struct FixerTests {
    private static let examiner = OpenAPIDoctor.Report.Examiner()
    private static let fixer = OpenAPIDoctor.Report.Fixer()

    private static let faulty = """
    openapi: 3.1.0
    info:
      title: Faulty
      version: "1"
    # a comment that must stay
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
        Name:
          type: string
          nullable: true
        Age: { type: integer, minimum: 100, maximum: 1 }
        Both:
          type: string
          readOnly: true
          writeOnly: true

    """

    @Test("one fix changes only what it must, and its finding is gone")
    func one() throws {
        let findings = Self.examiner.examine(yaml: Self.faulty)
        let parameter = try #require(findings.first { $0.what.hasPrefix("The path parameter") })
        let fixed = try #require(Self.fixer.fix(parameter, in: Self.faulty))
        let before = Self.faulty.components(separatedBy: "\n")
        let after = fixed.components(separatedBy: "\n")
        #expect(after.count == before.count + 1)
        #expect(after[11] == "          required: true", "\(after[9 ... 13])")
        #expect(after.filter { $0 != "          required: true" } == before)
    }

    @Test("fix all leaves no problem and no suggestion, and keeps the comment")
    func all() {
        let result = Self.fixer.fixAll(Self.faulty)
        #expect(Self.examiner.examine(yaml: result.text).isEmpty, "\(Self.examiner.examine(yaml: result.text))\n\(result.text)")
        #expect(result.fixed.count == Self.examiner.examine(yaml: Self.faulty).count)
        #expect(result.text.contains("# a comment that must stay"))
    }

    @Test("lines that end with two characters keep their ends")
    func windowsLineEnds() {
        let text = Self.faulty.replacingOccurrences(of: "\n", with: "\r\n")
        let result = Self.fixer.fixAll(text)
        #expect(Self.examiner.examine(yaml: result.text).isEmpty)
        #expect(result.text.components(separatedBy: "\r\n").count == result.text.components(separatedBy: "\n").count)
    }

    @Test("what has no safe fix is left as it is, and nothing is offered for it")
    func noFix() throws {
        let text = "openapi: 3.1.0\ninfo: { title: A, version: \"1\" }\nservers: [{ url: / }]\npaths: {}\ncomponents:\n  schemas:\n    P: { type: number, exclusiveMinimum: true }\n"
        let finding = try #require(Self.examiner.examine(yaml: text).first)
        #expect(Self.fixer.fix(finding, in: text) == nil)
        #expect(Self.fixer.fixAll(text).text == text)
    }

    @Test("every rule has a plain explanation")
    func explanations() {
        for finding in Self.examiner.examine(yaml: Self.faulty) {
            #expect(finding.explanation.count > 60, "\(finding.what)")
            #expect(finding.explanation != finding.rule)
        }
    }
}
