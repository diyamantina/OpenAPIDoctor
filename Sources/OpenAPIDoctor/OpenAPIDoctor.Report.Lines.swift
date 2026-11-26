import Foundation

extension OpenAPIDoctor.Report {
    /// A text as its lines, with the line end it uses, and the few questions an
    /// edit asks about them. Indexes count from zero.
    struct Lines {
        var all: [String]
        private let end: String

        init(_ text: String) {
            end = text.contains("\r\n") ? "\r\n" : "\n"
            all = text.components(separatedBy: end)
        }

        var text: String {
            all.joined(separator: end)
        }

        /// The number of spaces before a line's first other character.
        func indent(_ index: Int) -> Int {
            all[index].prefix { $0 == " " }.count
        }

        /// The column of the first key of a line: after the spaces and a list
        /// dash.
        func keyColumn(_ index: Int) -> Int {
            all[index].prefix { $0 == " " || $0 == "-" }.count
        }

        /// The lines that belong under a line: the ones after it that are
        /// further to the right, up to the first that is not.
        func block(under index: Int) -> [Int] {
            let outer = indent(index)
            var found: [Int] = []
            for next in all.indices.dropFirst(index + 1) {
                if all[next].allSatisfy(\.isWhitespace) {
                    continue
                }
                guard indent(next) > outer else { break }
                found.append(next)
            }
            return found
        }

        /// The line among these that starts, after spaces, with this key.
        func line(of key: String, in indexes: [Int]) -> Int? {
            indexes.first { all[$0].drop { $0 == " " || $0 == "-" }.hasPrefix(key + ":") }
        }

        /// The column of the lines directly under a line; two to the right
        /// when it has none.
        func childColumn(of index: Int) -> Int {
            block(under: index).first.map(indent) ?? indent(index) + 2
        }

        mutating func insert(_ words: String, at column: Int, after index: Int) {
            all.insert(String(repeating: " ", count: column) + words, at: index + 1)
        }
    }
}
