import Foundation
import OpenAPIKitCore
import PureYAML

extension OpenAPIDoctor.Report {
    /// The words for an error of the typed reading: what is wrong and how to
    /// fix it, short, without the parser's own account of what it tried.
    struct Wording: Sendable, Equatable {
        let what: String
        let how: String
        /// The keys from the piece that was read to the place of the fault.
        let path: [String]

        init(what: String, how: String, path: [String]) {
            self.what = what
            self.how = how
            self.path = path
        }

        init(_ error: any Swift.Error) {
            if let error = error as? PureYAML.Decoding.Error {
                self.init(error)
            } else if let error = error as? DecodingError {
                self.init(error)
            } else if let error = error as? any OpenAPIError {
                self.init(Self.reason(of: error.localizedDescription), path: error.codingPath.map(\.stringValue))
            } else {
                self.init(Self.reason(of: String(describing: error)), path: [])
            }
        }

        private init(_ error: PureYAML.Decoding.Error) {
            let path = OpenAPIDoctor.Validation.Validator.codingPath(for: error)
            switch error {
            case let .keyNotFound(key, _):
                self.init(missing: key, path: path)
            case let .typeMismatch(expected, actual, _):
                self.init(
                    what: "\(Self.noun(expected).capitalizedFirst) is expected here, and this is \(Self.noun(actual)).",
                    how: "Write \(Self.noun(expected)).",
                    path: path
                )
            case .integerOutOfRange:
                self.init(what: "This number is too large.", how: "Use a smaller number.", path: path)
            case .valueNotFound:
                self.init(what: "A value is missing here.", how: "Write a value, or remove the key.", path: path)
            }
        }

        private init(_ error: DecodingError) {
            let context = OpenAPIDoctor.Validation.Validator.context(for: error)
            let path = (context?.codingPath ?? []).map(\.stringValue)
            if case let .keyNotFound(key, _) = error {
                self.init(missing: key.stringValue, path: path)
            } else if let underlying = context?.underlyingError {
                let inner = Self(underlying)
                self.init(what: inner.what, how: inner.how, path: inner.path.isEmpty ? path : inner.path)
            } else {
                self.init(Self.reason(of: context?.debugDescription ?? String(describing: error)), path: path)
            }
        }

        private init(missing key: String, path: [String]) {
            // The path may or may not already end at the missing key.
            let parent = path.last == key ? Array(path.dropLast()) : path
            self.init(what: "`\(key)` is missing.", how: "Add `\(key)` here.", path: parent)
        }

        /// A reason of the parser put into our words, where it is one we know.
        init(_ reason: String, path: [String]) {
            if let keys = Self.strayKeys(in: reason) {
                self.init(strayKeys: keys, path: path)
            } else if reason.contains("positional path parameters must be explicitly set to required"),
                      let name = Self.quoted(in: reason)
            {
                self.init(what: "The path parameter `\(name)` is not marked as required.", how: "Add `required: true` to it.", path: path)
            } else if reason.contains("readOnly"), reason.contains("writeOnly") {
                self.init(what: "A schema cannot be both `readOnly` and `writeOnly`.", how: "Keep one of the two.", path: path)
            } else if let key = Self.missingKey(in: reason) {
                self.init(missing: key, path: path)
            } else {
                self.init(what: reason, how: "Correct this place and check again.", path: path)
            }
        }

        /// Keys the specification does not have and that lack the `x-` prefix of one's own keys.
        init(strayKeys keys: [String], path: [String]) {
            if keys.contains("$ref") {
                self.init(
                    what: "A `$ref` is not allowed here.",
                    how: "Write the part out here instead of referring to it, or move the reference to a place that takes one.",
                    path: path
                )
                return
            }
            self.init(
                what: "These keys are not allowed here: \(keys.sorted().joined(separator: ", ")).",
                how: "Put `x-` in front of each, or remove it.",
                path: path
            )
        }

        private static func strayKeys(in reason: String) -> [String]? {
            guard reason.contains("vendor extension property") else { return nil }
            let keys = OpenAPIDoctor.Validation.Validator.parseInvalidKeys(from: reason)
            return keys.isEmpty ? nil : keys
        }

        /// The last thing the parser says: after its account of each form it
        /// tried, the reason of the one that came closest.
        static func reason(of description: String) -> String {
            var text = description.components(separatedBy: "could not be decoded because:\n").last ?? description
            // A decoding error written out in full: only its description is for a person.
            if let after = text.components(separatedBy: "Debug description: ").dropFirst().first {
                text = after.components(separatedBy: ". Underlying error:").first ?? after
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.hasSuffix("..") {
                text.removeLast()
            }
            return text
        }

        /// The word between the first pair of backticks.
        private static func quoted(in text: String) -> String? {
            let pieces = text.components(separatedBy: "`")
            return pieces.count > 2 ? pieces[1] : nil
        }

        private static func missingKey(in reason: String) -> String? {
            guard reason.contains("Missing required key") || reason.contains("Expected to find") else { return nil }
            let pieces = reason.components(separatedBy: CharacterSet(charactersIn: "'`"))
            return pieces.count > 2 ? pieces[1] : nil
        }

        private static func noun(_ kind: String) -> String {
            switch kind.lowercased() {
            case "bool", "boolean": "true or false"
            case "double", "int", "integer", "number", "float": "a number"
            case "string": "text"
            case "mapping", "dictionary": "a set of keys and values"
            case "sequence", "array": "a list"
            case "null": "empty"
            default: kind
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
