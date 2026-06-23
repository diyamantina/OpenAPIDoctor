// PureYAMLValueAccess
//
// Internal ergonomic accessors over PureYAML's ``Model/Value`` tree. The
// YAML-level scan (``Synthesis/Scanner``) and the mutation helpers
// (``Repair/Repairer``) previously leaned on Yams's `Node` conveniences
// (`node.mapping`, `node.string`, `node.sequence`); these mirror that shape
// on PureYAML's ordered value model so those passes read the same way.

import PureYAML

extension PureYAML.Model.Value {
    /// The mapping payload when this value is a mapping; `nil` otherwise.
    var mapping: PureYAML.Model.Mapping? {
        guard case let .mapping(mapping) = self else { return nil }
        return mapping
    }

    /// The scalar text when this value is a string scalar; `nil` otherwise.
    ///
    /// Intentionally narrow: a non-string scalar (`.int`, `.double`, `.bool`)
    /// returns `nil`, matching Yams's `Node.string`, which only yields a value
    /// for string-tagged scalars.
    var scalarString: String? {
        guard case let .string(string) = self else { return nil }
        return string
    }

    /// The sequence payload when this value is a sequence; `nil` otherwise.
    var sequence: [PureYAML.Model.Value]? {
        guard case let .sequence(values) = self else { return nil }
        return values
    }
}
