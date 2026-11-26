import Foundation

extension OpenAPIDoctor.Report {
    /// The edit of the lines for each kind of finding. An edit may be wrong for
    /// an unusual layout: ``Fixer`` examines the result and offers it only when
    /// it worked.
    enum Edit {
        private static let typeWords = [
            "int": "integer", "int32": "integer", "int64": "integer", "long": "integer", "float": "number", "double": "number",
            "decimal": "number", "bool": "boolean", "str": "string", "text": "string", "list": "array", "dict": "object", "map": "object",
        ]

        static func apply(_ finding: Finding, to lines: inout Lines) -> Bool {
            let what = finding.what
            if what.hasPrefix("The file lists no") {
                return appendServers(&lines)
            }
            guard let number = finding.line, lines.all.indices.contains(number - 1) else { return false }
            let index = number - 1
            if what.hasPrefix("These keys are not allowed") {
                let names = what.components(separatedBy: ": ").dropFirst().joined(separator: ": ").dropLast()
                let keys = names.components(separatedBy: ", ")
                // A key that starts with `$` means something to the format; renaming it would change what the file says.
                guard !keys.contains(where: { $0.hasPrefix("$") }) else { return false }
                return own(keys, at: index, lines: &lines)
            }
            if finding.place.last == "info", what == "`title` is missing." {
                return set("title", "My service", at: index, lines: &lines)
            }
            if finding.place.last == "info", what == "`version` is missing." {
                return set("version", "1.0.0", at: index, lines: &lines)
            }
            if what.hasPrefix("The path parameter") {
                return set("required", "true", at: index, lines: &lines)
            }
            if what.hasPrefix("The operationId") {
                return rename(index, lines: &lines)
            }
            if what.hasSuffix("is not a type.") {
                return retype(index, lines: &lines)
            }
            if what.hasPrefix("`nullable`") {
                return removeNullable(index, lines: &lines)
            }
            if what.contains("is larger than") {
                let words = what.components(separatedBy: "`")
                guard words.count > 3 else { return false }
                return swap(words[1], words[3], at: index, lines: &lines)
            }
            if what.hasPrefix("A schema cannot be both") {
                return remove("writeOnly", at: index, lines: &lines)
            }
            if what == "`description` is missing." {
                return set("description", "Describe this answer", at: index, lines: &lines)
            }
            if what.hasPrefix("This operation has no") {
                // The made up name may be taken already; a number sets it apart.
                let made = madeUpId(finding.place)
                var name = made
                var number = 2
                let whole = lines.text
                while whole.contains("operationId: \(name)\n") || whole.contains("operationId: \(name)\r") || whole.contains("operationId: \(name),") {
                    name = "\(made)_\(number)"
                    number += 1
                }
                return set("operationId", name, at: index, lines: &lines)
            }
            return false
        }

        // MARK: Steps shared by the edits

        /// Whether the line holds its mapping in braces.
        private static func isInline(_ line: String) -> Bool {
            line.contains("{ ") || line.hasSuffix("{}") || line.contains(": {")
        }

        /// The range of the value written after `key:` on a line.
        private static func value(of key: String, in line: String) -> Range<String.Index>? {
            guard let found = line.range(of: key + ":") else { return nil }
            var start = found.upperBound
            while start < line.endIndex, line[start] == " " {
                start = line.index(after: start)
            }
            var end = start
            while end < line.endIndex, !",}#".contains(line[end]) {
                end = line.index(after: end)
            }
            while end > start, line[line.index(before: end)] == " " {
                end = line.index(before: end)
            }
            return start < end ? start ..< end : nil
        }

        /// Sets `key: words` in the mapping that starts on this line.
        private static func set(_ key: String, _ words: String, at index: Int, lines: inout Lines) -> Bool {
            let line = lines.all[index]
            if isInline(line), let open = line.firstIndex(of: "{") {
                if let old = value(of: key, in: line) {
                    lines.all[index].replaceSubrange(old, with: words)
                } else {
                    let rest = line[line.index(after: open)...].drop { $0 == " " }
                    let comma = rest.hasPrefix("}") ? " " : ", "
                    lines.all[index] = line[...open] + " \(key): \(words)\(comma)" + rest
                }
                return true
            }
            let isItem = line.drop { $0 == " " }.hasPrefix("- ")
            let under = lines.block(under: index)
            let column = isItem ? lines.keyColumn(index) : lines.childColumn(of: index)
            if let existing = lines.line(of: key, in: under), let old = value(of: key, in: lines.all[existing]) {
                lines.all[existing].replaceSubrange(old, with: words)
            } else {
                lines.insert("\(key): \(words)", at: column, after: index)
            }
            return true
        }

        /// Removes `key: …` from the mapping that starts on this line.
        private static func remove(_ key: String, at index: Int, lines: inout Lines) -> Bool {
            let line = lines.all[index]
            if isInline(line), let found = line.range(of: key + ":"), let old = value(of: key, in: line) {
                var start = found.lowerBound
                var end = old.upperBound
                if end < line.endIndex, line[end] == "," {
                    end = line.index(after: end)
                    while end < line.endIndex, line[end] == " " {
                        end = line.index(after: end)
                    }
                } else {
                    while start > line.startIndex, ", ".contains(line[line.index(before: start)]) {
                        start = line.index(before: start)
                    }
                }
                lines.all[index].removeSubrange(start ..< end)
                return true
            }
            guard let found = lines.line(of: key, in: lines.block(under: index)) else { return false }
            lines.all.remove(at: found)
            return true
        }

        /// The line that holds `key:` for the mapping that starts here.
        private static func holder(of key: String, from index: Int, lines: Lines) -> Int? {
            lines.all[index].contains(key + ":") ? index : lines.line(of: key, in: lines.block(under: index))
        }

        // MARK: The edits

        /// Puts `x-` in front of these keys of the mapping that starts here, so that they count as one's own keys and keep their values.
        private static func own(_ keys: [String], at index: Int, lines: inout Lines) -> Bool {
            if isInline(lines.all[index]) {
                for key in keys {
                    guard let found = lines.all[index].range(of: " \(key):") else { return false }
                    lines.all[index].replaceSubrange(found, with: " x-\(key):")
                }
                return true
            }
            let column = lines.keyColumn(index)
            let own = [index] + lines.block(under: index).filter { lines.indent($0) == column }
            for key in keys {
                guard let found = lines.line(of: key, in: own), let place = lines.all[found].range(of: "\(key):") else { return false }
                lines.all[found].replaceSubrange(place, with: "x-\(key):")
            }
            return true
        }

        private static func rename(_ index: Int, lines: inout Lines) -> Bool {
            guard let old = value(of: "operationId", in: lines.all[index]) else { return false }
            let name = lines.all[index][old].trimmingCharacters(in: ["\"", "'"])
            var number = 2
            let whole = lines.text
            while whole.contains("\(name)_\(number)") {
                number += 1
            }
            lines.all[index].replaceSubrange(old, with: "\(name)_\(number)")
            return true
        }

        private static func retype(_ index: Int, lines: inout Lines) -> Bool {
            guard let found = holder(of: "type", from: index, lines: lines), let old = value(of: "type", in: lines.all[found]) else { return false }
            let word = lines.all[found][old].trimmingCharacters(in: ["\"", "'"]).lowercased()
            guard let right = typeWords[word] else { return false }
            lines.all[found].replaceSubrange(old, with: right)
            return true
        }

        private static func removeNullable(_ index: Int, lines: inout Lines) -> Bool {
            guard let nullable = holder(of: "nullable", from: index, lines: lines),
                  let said = value(of: "nullable", in: lines.all[nullable])
            else { return false }
            if lines.all[nullable][said] == "true" {
                guard let type = holder(of: "type", from: index, lines: lines), let old = value(of: "type", in: lines.all[type]) else { return false }
                let word = String(lines.all[type][old])
                guard !word.hasPrefix("[") else { return false }
                lines.all[type].replaceSubrange(old, with: "[\(word), \"null\"]")
            }
            return remove("nullable", at: index, lines: &lines)
        }

        private static func swap(_ low: String, _ high: String, at index: Int, lines: inout Lines) -> Bool {
            guard let first = holder(of: low, from: index, lines: lines), let second = holder(of: high, from: index, lines: lines),
                  let lowRange = value(of: low, in: lines.all[first]), let highRange = value(of: high, in: lines.all[second])
            else { return false }
            let lowWords = String(lines.all[first][lowRange])
            let highWords = String(lines.all[second][highRange])
            lines.all[first].replaceSubrange(lowRange, with: highWords)
            guard let again = value(of: high, in: lines.all[second]) else { return false }
            lines.all[second].replaceSubrange(again, with: lowWords)
            return true
        }

        /// A name from the method and the path: `get` and `/items/{id}` give
        /// `getItemsId`.
        private static func madeUpId(_ place: [String]) -> String {
            guard place.count >= 3 else { return "operation" }
            let words = place[1].split { !$0.isLetter && !$0.isNumber }
            return place[2] + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        }

        private static func appendServers(_ lines: inout Lines) -> Bool {
            let ending = lines.all.last == ""
            if ending {
                lines.all.removeLast()
            }
            lines.all += ["servers:", "  - url: /"]
            if ending {
                lines.all.append("")
            }
            return true
        }
    }
}
