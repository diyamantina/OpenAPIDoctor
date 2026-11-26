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

        func first(in value: PureYAML.Model.Value) -> Diagnosis? {
            walk(value, path: [], childrenAreNames: false)
        }

        private func walk(_ value: PureYAML.Model.Value, path: [String], childrenAreNames: Bool) -> Diagnosis? {
            if let items = value.sequence {
                for (index, item) in items.enumerated() {
                    if let found = walk(item, path: path + [String(index)], childrenAreNames: false) {
                        return found
                    }
                }
                return nil
            }
            guard let mapping = value.mapping else { return nil }
            if !childrenAreNames, let details = fault(of: mapping) {
                return Diagnosis(kind: .inconsistency(codingPath: path, details: details, subjectName: "JSONSchema"))
            }
            for pair in mapping.pairs {
                guard let key = pair.keyNode.stringValue else { continue }
                if !childrenAreNames, Self.data.contains(key) || key.hasPrefix("x-") {
                    continue
                }
                let names = !childrenAreNames && Self.named.contains(key)
                if let found = walk(pair.value, path: path + [key], childrenAreNames: names) {
                    return found
                }
            }
            return nil
        }

        private func fault(of mapping: PureYAML.Model.Mapping) -> String? {
            guard let type = mapping["type"], type.scalarString != nil || type.sequence != nil else { return nil }
            if nullableIsGone, case .bool? = mapping["nullable"] {
                return "`nullable` is not a keyword of OpenAPI 3.1 and is ignored: add \"null\" to `type` instead."
            }
            for (low, high) in Self.bounds {
                if let least = Self.number(mapping[low]), let most = Self.number(mapping[high]), least > most {
                    return "`\(low)` is larger than `\(high)`, so no value can meet both."
                }
            }
            return nil
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
