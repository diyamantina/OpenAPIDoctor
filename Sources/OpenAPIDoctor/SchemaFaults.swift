// SchemaFaults
//
// A walk over the YAML tree for faults in schemas that OpenAPIKit accepts
// without a word. Lives on `OpenAPIDoctor.Validation`.

import PureYAML

extension OpenAPIDoctor.Validation {
    /// Finds the first schema, in document order, that either uses the
    /// `nullable` keyword in a 3.1 document (3.1 ignores it, so the intent
    /// is lost) or states bounds no value can meet.
    ///
    /// A schema is recognised by its `type` word. Example data, default
    /// values, enumerations and extensions are not walked; a property or a
    /// component that merely has one of those names is.
    struct SchemaFaults: Sendable {
        /// `true` for a 3.1 document, where `nullable` is not a keyword.
        let nullableIsGone: Bool

        private static let data: Set<String> = ["example", "examples", "default", "enum", "const"]
        /// The keys whose children are names the author chose, not keywords.
        private static let named: Set<String> = ["properties", "patternProperties", "$defs", "schemas"]
        private static let bounds = [("minimum", "maximum"), ("minLength", "maxLength"), ("minItems", "maxItems")]

        /// One fault of one schema.
        struct Fault {
            let place: [String]
            let what: String
            let how: String
        }

        private static let types: Set<String> = ["string", "number", "integer", "boolean", "object", "array", "null"]

        func first(in value: PureYAML.Model.Value) -> Diagnosis? {
            // A type that does not exist is the typed reading's own error.
            all(in: value).first { !$0.what.hasSuffix("is not a type.") }.map { fault in
                Diagnosis(kind: .inconsistency(codingPath: fault.place, details: "\(fault.what) \(fault.how)", subjectName: "JSONSchema"))
            }
        }

        /// Every fault, in document order.
        func all(in value: PureYAML.Model.Value) -> [Fault] {
            walk(value, path: [], childrenAreNames: false)
        }

        private func walk(_ value: PureYAML.Model.Value, path: [String], childrenAreNames: Bool) -> [Fault] {
            if let items = value.sequence {
                return items.enumerated().flatMap { index, item in
                    walk(item, path: path + [String(index)], childrenAreNames: false)
                }
            }
            guard let mapping = value.mapping else { return [] }
            var found = childrenAreNames ? [] : faults(of: mapping, at: path)
            for pair in mapping.pairs {
                guard let key = pair.keyNode.stringValue else { continue }
                if !childrenAreNames, Self.data.contains(key) || key.hasPrefix("x-") {
                    continue
                }
                let names = !childrenAreNames && Self.named.contains(key)
                found += walk(pair.value, path: path + [key], childrenAreNames: names)
            }
            return found
        }

        private func faults(of mapping: PureYAML.Model.Mapping, at path: [String]) -> [Fault] {
            guard let type = mapping["type"], type.scalarString != nil || type.sequence != nil else { return [] }
            var found: [Fault] = []
            // A security scheme has a `type` too; its words are not schema types.
            if let word = type.scalarString, !Self.types.contains(word), !path.contains("securitySchemes") {
                found.append(Fault(
                    place: path + ["type"],
                    what: "`\(word)` is not a type.",
                    how: "Use string, number, integer, boolean, object, array or null."
                ))
            }
            if nullableIsGone, case .bool? = mapping["nullable"] {
                found.append(Fault(
                    place: path,
                    what: "`nullable` is not a keyword of OpenAPI 3.1 and is ignored.",
                    how: "Remove it and add \"null\" to `type`, as in `type: [string, \"null\"]`."
                ))
            }
            for (low, high) in Self.bounds {
                if let least = Self.number(mapping[low]), let most = Self.number(mapping[high]), least > most {
                    found.append(Fault(
                        place: path,
                        what: "`\(low)` is larger than `\(high)`, so no value can meet both.",
                        how: "Make `\(low)` smaller than or equal to `\(high)`."
                    ))
                }
            }
            return found
        }

        private static func number(_ value: PureYAML.Model.Value?) -> Double? {
            switch value {
            case let .int(number)?: Double(number)
            case let .double(number)?: number
            default: nil
            }
        }
    }
}
