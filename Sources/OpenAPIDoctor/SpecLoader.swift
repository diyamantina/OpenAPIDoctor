// SpecLoader
//
// Loads an OpenAPI spec from disk, optionally resolving external
// `$ref` references via Stitcher. Lives on `OpenAPIDoctor.Loading`.

import Foundation
import Stitcher

extension OpenAPIDoctor.Loading {

    /// Loads an OpenAPI spec from a file path.
    ///
    /// When `resolveExternalRefs` is `true` (default), external `$ref`
    /// references are recursively resolved into one in-memory document
    /// via [Stitcher](https://github.com/mihaelamj/Stitcher). The
    /// returned string is always YAML; the caller passes it straight
    /// to ``Validator/validate(yaml:)``.
    ///
    /// Internal refs (those that start with `#`) are passed through
    /// unchanged — only cross-file refs are resolved.
    public struct SpecLoader: Sendable {

        public init() {}

        /// Load a spec at a file path. Auto-detects JSON via the `.json`
        /// extension; everything else is treated as YAML. JSON is
        /// converted to YAML by Stitcher's pipeline so the output is
        /// always a YAML string ready for ``Validator/validate(yaml:)``.
        ///
        /// - Parameters:
        ///   - path: Filesystem path to the spec.
        ///   - resolveExternalRefs: When `true`, runs Stitcher's
        ///     resolver to merge external `$ref` files into one
        ///     document.
        /// - Returns: A YAML string containing the loaded spec.
        public func load(
            from path: String,
            resolveExternalRefs: Bool = true,
        ) async throws -> String {
            let url = URL(fileURLWithPath: path)
            if resolveExternalRefs {
                let stitcher = Stitcher()
                return try await stitcher.stitch(from: url)
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
}
