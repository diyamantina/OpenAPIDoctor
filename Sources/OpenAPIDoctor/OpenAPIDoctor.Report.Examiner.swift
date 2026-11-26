import OpenAPIKit
import OpenAPIKit30
import PureYAML

public extension OpenAPIDoctor.Report {
    /// Finds as many faults of a document as it can in one pass. The typed
    /// reading stops at its first error, so the document is read piece by
    /// piece (the information, each operation, each component), and each piece
    /// gives its own fault; checks that need the whole file are made on the
    /// text's tree.
    struct Examiner: Sendable {
        private typealias Value = PureYAML.Model.Value
        private typealias Located = PureYAML.Model.LocatedValue

        private static let methods: Set<String> = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]

        public init() {}

        /// The findings: problems in the order of the file, then suggestions.
        /// An empty list means nothing was found.
        public func examine(yaml: String) -> [Finding] {
            let tree: Located
            do {
                tree = try PureYAML.parseLocated(yaml)
            } catch {
                return [Self.notYAML(error)]
            }
            let document = tree.value
            guard let top = document.mapping else {
                return [Finding(line: 1, place: [], what: "The file is not an OpenAPI document.", how: "Start it with `openapi:`, `info:` and `paths:`.")]
            }
            guard let version = Self.text(top["openapi"]), version.hasPrefix("3.0") || version.hasPrefix("3.1") else {
                return [Self.version(Self.text(top["openapi"]), tree: tree)]
            }
            let old = version.hasPrefix("3.0")
            var problems: [Finding] = []
            if top["info"] == nil {
                problems.append(Finding(line: 1, place: [], what: "`info` is missing.", how: "Add `info:` with a `title` and a `version`."))
            }
            for piece in Self.pieces(of: top) {
                if let error = piece.fault(old: old) {
                    let wording = Wording(error)
                    let place = wording.path.starts(with: piece.place) ? wording.path : piece.place + wording.path
                    problems.append(Finding(line: Self.line(of: place, in: tree), place: place, what: wording.what, how: wording.how))
                }
            }
            problems += Self.repeatedIds(top, tree: tree)
            let schemaFaults = OpenAPIDoctor.Validation.SchemaFaults(nullableIsGone: !old).all(in: document).map { fault in
                Finding(line: Self.line(of: fault.place, in: tree), place: fault.place, what: fault.what, how: fault.how)
            }
            // Where our own words name a fault, the reading's account of the same place, or of the piece that holds it, is left out.
            let ours = schemaFaults + Self.responsesWithoutDescription(top, tree: tree)
            problems.removeAll { finding in
                ours.contains { $0.line == finding.line || $0.place.starts(with: finding.place) && !finding.place.isEmpty && finding.place.first == "components" }
            }
            problems += ours
            if problems.isEmpty {
                problems += Self.whole(yaml, tree: tree)
            }
            problems.sort { ($0.line ?? 0, $0.what) < ($1.line ?? 0, $1.what) }
            return problems + Self.suggestions(top, tree: tree)
        }

        // MARK: The pieces

        /// A key of the path from the top of the document.
        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? {
                nil
            }

            init(_ text: String) {
                stringValue = text
            }

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue _: Int) {
                nil
            }
        }

        /// One part of a document that can be read on its own.
        private struct Piece {
            enum Kind { case info, operation, schema, response, parameter, requestBody, securityScheme }

            let kind: Kind
            let place: [String]
            let value: Value

            /// The error of reading this piece, if it cannot be read.
            func fault(old: Bool) -> (any Swift.Error)? {
                // The reading's own error messages take the path from the top of
                // the document for granted, so the piece is read with it.
                let decoder = PureYAML.Decoding.Decoder(value: value, codingPath: place.map(Key.init), validatesInput: false)
                do {
                    switch (kind, old) {
                    case (.info, false): _ = try OpenAPIKit.OpenAPI.Document.Info(from: decoder)
                    case (.info, true): _ = try OpenAPIKit30.OpenAPI.Document.Info(from: decoder)
                    case (.operation, false): _ = try OpenAPIKit.OpenAPI.Operation(from: decoder)
                    case (.operation, true): _ = try OpenAPIKit30.OpenAPI.Operation(from: decoder)
                    case (.schema, false): _ = try OpenAPIKit.JSONSchema(from: decoder)
                    case (.schema, true): _ = try OpenAPIKit30.JSONSchema(from: decoder)
                    case (.response, false): _ = try OpenAPIKit.OpenAPI.Response(from: decoder)
                    case (.response, true): _ = try OpenAPIKit30.OpenAPI.Response(from: decoder)
                    case (.parameter, false): _ = try OpenAPIKit.OpenAPI.Parameter(from: decoder)
                    case (.parameter, true): _ = try OpenAPIKit30.OpenAPI.Parameter(from: decoder)
                    case (.requestBody, false): _ = try OpenAPIKit.OpenAPI.Request(from: decoder)
                    case (.requestBody, true): _ = try OpenAPIKit30.OpenAPI.Request(from: decoder)
                    case (.securityScheme, false): _ = try OpenAPIKit.OpenAPI.SecurityScheme(from: decoder)
                    case (.securityScheme, true): _ = try OpenAPIKit30.OpenAPI.SecurityScheme(from: decoder)
                    }
                    return nil
                } catch {
                    return error
                }
            }
        }

        private static func pieces(of top: PureYAML.Model.Mapping) -> [Piece] {
            var pieces: [Piece] = []
            if let info = top["info"] {
                pieces.append(Piece(kind: .info, place: ["info"], value: info))
            }
            for (path, item) in entries(top["paths"]) {
                for (method, operation) in entries(item) where methods.contains(method) {
                    pieces.append(Piece(kind: .operation, place: ["paths", path, method], value: operation))
                }
            }
            let components = top["components"]?.mapping
            let kinds: [(String, Piece.Kind)] = [
                ("schemas", .schema), ("responses", .response), ("parameters", .parameter),
                ("requestBodies", .requestBody), ("securitySchemes", .securityScheme),
            ]
            for (key, kind) in kinds {
                for (name, value) in entries(components?[key]) where value.mapping?["$ref"] == nil {
                    pieces.append(Piece(kind: kind, place: ["components", key, name], value: value))
                }
            }
            return pieces
        }

        // MARK: Checks of the whole file

        /// A response written in place must have a `description`; the reading's own message does not say that this is what is missing.
        private static func responsesWithoutDescription(_ top: PureYAML.Model.Mapping, tree: Located) -> [Finding] {
            var responses: [(place: [String], value: Value)] = []
            for (path, item) in entries(top["paths"]) {
                for (method, operation) in entries(item) where methods.contains(method) {
                    for (status, response) in entries(operation.mapping?["responses"]) {
                        responses.append((["paths", path, method, "responses", status], response))
                    }
                }
            }
            for (name, response) in entries(top["components"]?.mapping?["responses"]) {
                responses.append((["components", "responses", name], response))
            }
            return responses.compactMap { place, value in
                guard let mapping = value.mapping, mapping["$ref"] == nil, mapping["description"] == nil else { return nil }
                return Finding(line: line(of: place, in: tree), place: place, what: "`description` is missing.", how: "Add `description` here.")
            }
        }

        private static func repeatedIds(_ top: PureYAML.Model.Mapping, tree: Located) -> [Finding] {
            var first: [String: Int] = [:]
            var findings: [Finding] = []
            for (path, item) in entries(top["paths"]) {
                for (method, operation) in entries(item) where methods.contains(method) {
                    guard let id = text(operation.mapping?["operationId"]) else { continue }
                    let place = ["paths", path, method, "operationId"]
                    let line = line(of: place, in: tree)
                    if let earlier = first[id] {
                        findings.append(Finding(
                            line: line,
                            place: place,
                            what: "The operationId `\(id)` is already used on line \(earlier).",
                            how: "Give each operation its own operationId."
                        ))
                    } else if let line {
                        first[id] = line
                    }
                }
            }
            return findings
        }

        /// When every piece is sound: what the reading of the whole document
        /// and its own checks still refuse.
        private static func whole(_ yaml: String, tree: Located) -> [Finding] {
            let diagnosis = OpenAPIDoctor.Validation.Validator().validate(yaml: yaml)
            let place: [String]
            let details: String
            switch diagnosis.kind {
            case let .inconsistency(path, text, _): (place, details) = (path, text)
            case let .decodingError(path, text): (place, details) = (path, text)
            case let .unknown(text): (place, details) = ([], text)
            case let .vendorExtensionPrefix(path, keys, _):
                (place, details) = (path, "These keys are not allowed here: \(keys.joined(separator: ", ")).")
            case .ok, .missingServers, .missingOperationId, .fileError: return []
            }
            let finding = Finding(
                line: line(of: place, in: tree),
                place: place,
                what: Wording.reason(of: details),
                how: "Correct this place and check again."
            )
            return [finding]
        }

        private static func suggestions(_ top: PureYAML.Model.Mapping, tree: Located) -> [Finding] {
            var findings: [Finding] = []
            if top["servers"] == nil {
                findings.append(Finding(
                    severity: .suggestion,
                    line: 1,
                    place: [],
                    what: "The file lists no `servers`.",
                    how: "Add `servers:` with the address of the service, for example `- url: /`."
                ))
            }
            for (path, item) in entries(top["paths"]) {
                for (method, operation) in entries(item) where methods.contains(method) && operation.mapping?["operationId"] == nil {
                    let place = ["paths", path, method]
                    findings.append(Finding(
                        severity: .suggestion,
                        line: line(of: place, in: tree),
                        place: place,
                        what: "This operation has no `operationId`.",
                        how: "Add one: it becomes the name of the method in the generated code."
                    ))
                }
            }
            return findings
        }

        // MARK: The tree

        private static func entries(_ value: Value?) -> [(String, Value)] {
            value?.mapping?.pairs.compactMap { pair in pair.keyNode.stringValue.map { ($0, pair.value) } } ?? []
        }

        private static func text(_ value: Value?) -> String? {
            switch value {
            case let .string(text)?: text
            case let .int(number)?: String(number)
            case let .double(number)?: String(number)
            default: nil
            }
        }

        /// The line of the deepest part of a place that the file has.
        private static func line(of place: [String], in tree: Located) -> Int? {
            var node = tree
            var line = node.range.start.line
            for part in place {
                if case let .mapping(pairs, _) = node, let pair = pairs.first(where: { $0.keyNode.stringValue == part }) {
                    line = pair.keyRange.start.line
                    node = pair.value
                } else if case let .sequence(items, _) = node,
                          let index = Int(part.replacingOccurrences(of: "Index ", with: "")), items.indices.contains(index)
                {
                    node = items[index]
                    line = node.range.start.line
                } else {
                    break
                }
            }
            return line
        }

        private static func notYAML(_ error: any Swift.Error) -> Finding {
            let words = String(describing: error)
            let after = words.components(separatedBy: "line ").dropFirst().first
            let line = after.flatMap { Int($0.prefix(while: \.isNumber)) }
            return Finding(line: line, place: [], what: "The text is not valid YAML here.", how: "Look for a missing bracket, quote or colon, and for tabs.")
        }

        private static func version(_ found: String?, tree: Located) -> Finding {
            Finding(
                line: line(of: ["openapi"], in: tree),
                place: [],
                what: found.map { "OpenAPI version `\($0)` is not supported." } ?? "`openapi` is missing.",
                how: "Write `openapi: 3.1.0` or a 3.0 version."
            )
        }
    }
}
