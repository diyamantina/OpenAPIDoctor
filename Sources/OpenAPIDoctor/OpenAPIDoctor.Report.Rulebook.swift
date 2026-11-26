import Foundation

extension OpenAPIDoctor.Report {
    /// For each kind of finding: the rule it breaks, in our words, with where
    /// it stands, and the fix written as YAML where one can be shown. The kind
    /// is told by the finding's own sentence.
    enum Rulebook {
        static func entry(for finding: Finding) -> (rule: String, example: String?) {
            let what = finding.what
            let name = quoted(what) ?? ""
            if what.hasPrefix("The path parameter") {
                return (
                    "OpenAPI, Parameter Object: when `in` is `path`, `required` must be present and `true`.",
                    "- name: \(name)\n  in: path\n  required: true"
                )
            }
            if what.hasPrefix("The operationId") {
                return ("OpenAPI, Operation Object: `operationId` must be unique among all operations.", "operationId: \(name)_2")
            }
            if what.hasSuffix("is not a type.") {
                return ("JSON Schema, `type`: string, number, integer, boolean, object, array or null.", "type: integer")
            }
            if what.hasPrefix("`nullable`") {
                return (
                    "OpenAPI 3.1 follows JSON Schema 2020-12, which has no `nullable`: an empty value is a type of its own.",
                    "type: [string, \"null\"]"
                )
            }
            if what.contains("is larger than") {
                let pair = what.components(separatedBy: "`")
                let low = pair.count > 1 ? pair[1] : "minimum"
                let high = pair.count > 3 ? pair[3] : "maximum"
                return (
                    "Not forbidden by the specification, but JSON Schema asks a value to meet both bounds, and none can.",
                    "\(low): 1\n\(high): 100"
                )
            }
            if what.hasPrefix("A schema cannot be both") {
                return ("OpenAPI, Schema Object: a property must not be both `readOnly` and `writeOnly`.", "readOnly: true")
            }
            if what == "`description` is missing." {
                return ("OpenAPI: `description` is a required field of this object.", "description: What this means")
            }
            if what == "`info` is missing." {
                return ("OpenAPI Object: `info` is required.", "info:\n  title: My service\n  version: 1.0.0")
            }
            if what.hasSuffix("is missing.") {
                return ("OpenAPI: `\(name)` is a required field of this object.", "\(name): ...")
            }
            if what.hasSuffix("is not supported.") {
                return ("OpenAPI Object: `openapi` names the version of the format; 3.0 and 3.1 are read here.", "openapi: 3.1.0")
            }
            if what.hasPrefix("The text is not valid YAML") {
                return ("YAML 1.2: the text must be well formed.", "key: [one, two]")
            }
            if what.hasPrefix("The file lists no") {
                return ("OpenAPI Object: `servers` is optional; without it the address is `/`.", "servers:\n  - url: /")
            }
            if what.hasPrefix("This operation has no") {
                return ("OpenAPI, Operation Object: `operationId` is optional; code generators name methods by it.", "operationId: listItems")
            }
            return ("OpenAPI: each field takes the kind of value the specification gives it.", nil)
        }

        /// The word between the first pair of backticks.
        private static func quoted(_ text: String) -> String? {
            let pieces = text.components(separatedBy: "`")
            return pieces.count > 2 ? pieces[1] : nil
        }
    }
}
