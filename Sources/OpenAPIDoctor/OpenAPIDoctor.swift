// OpenAPIDoctor
//
// Root namespace for the spec-diagnosis and -repair library. All
// concrete types live in extensions on this enum or its sub-namespaces.

/// Root namespace for the OpenAPI spec doctor library.
///
/// Diagnoses an OpenAPI 3.0 or 3.1 document by decoding it through the
/// same parser (``mattpolzin/OpenAPIKit``) that `swift-openapi-generator`
/// uses, then categorising the resulting errors into structured
/// `Diagnosis` values. Use ``Validator`` to validate a spec, and
/// ``Diagnosis`` to interpret the result.
///
/// Multi-file specs (with external `$ref` references) are auto-resolved
/// by ``SpecLoader`` via the
/// [`Stitcher`](https://github.com/mihaelamj/Stitcher) library before
/// validation, so a single entry point handles every spec shape.
public enum OpenAPIDoctor {

    /// Sub-namespace for validation types: ``Validator``, ``Diagnosis``,
    /// ``DiagnosisKind``.
    public enum Validation {}

    /// Sub-namespace for spec-loading types: ``SpecLoader``, ``SpecFormat``.
    public enum Loading {}

    /// Sub-namespace for repair types: ``Repairer``, ``RepairResult``,
    /// ``RepairRound``.
    public enum Repair {}
}
