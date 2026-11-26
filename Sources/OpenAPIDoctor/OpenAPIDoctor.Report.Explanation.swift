extension OpenAPIDoctor.Report {
    /// For each kind of finding, why it matters, for a reader who does not
    /// know the specification.
    enum Explanation {
        static func of(_ finding: Finding) -> String {
            let what = finding.what
            if what.hasPrefix("A `$ref` is not allowed") {
                return "A reference says that the part is written somewhere else. Only some parts of the file may be written that way; "
                    + "here a tool expects the part itself and cannot follow the reference."
            }
            if what.hasPrefix("These keys are not allowed") {
                return "Each part of the file knows a fixed set of keys. You may add your own, but their names must start with x- "
                    + "so that tools know to leave them alone; otherwise a tool takes them for mistakes."
            }
            if what.hasPrefix("The path parameter") {
                return "A part of the address in braces is filled in with a value every time the address is used. Without a value there is no address to call, "
                    + "so the specification wants you to say plainly that the value is always needed."
            }
            if what.hasPrefix("The operationId") {
                return "The operationId is the name of one action of your service. Code generators turn it into the name of a method, "
                    + "and two methods cannot share one name, so the second one would stop the build."
            }
            if what.hasSuffix("is not a type.") {
                return "The type says what kind of value is sent. Only a fixed set of words is understood, "
                    + "so any other word leaves programs unable to tell whether to expect text, a number or something else."
            }
            if what.hasPrefix("`nullable`") {
                return "Older versions used a separate word to say that a value may be empty. Version 3.1 dropped it, and readers now skip it, "
                    + "so the value is treated as always present although you meant that it may be missing."
            }
            if what.contains("is larger than") {
                return "The two limits say how small and how large a value may be. When the lower limit is above the upper one there is no value "
                    + "between them, so every request that uses this field would be refused."
            }
            if what.hasPrefix("A schema cannot be both") {
                return "One word says that a value is only ever sent by the server, the other that it is only ever sent to the server. "
                    + "A value cannot be both, and programs cannot decide where it belongs."
            }
            if what == "`description` is missing." {
                return "Every answer of your service needs a few words saying what it means. People read them in the documentation, "
                    + "and the specification does not accept an answer without them."
            }
            if what == "`info` is missing." {
                return "The start of the file names your service and its version. Tools use them to title the documentation and the generated code, "
                    + "and the file is not accepted without them."
            }
            if what.hasSuffix("is missing.") {
                return "The specification lists the words that must be present in each part of the file. Without this one the part is incomplete, "
                    + "and tools cannot read it."
            }
            if what.hasSuffix("is not supported.") {
                return "The first line says which version of the format the file follows. Tools read a file by the rules of that version, "
                    + "and this one is not a version that is read here."
            }
            if what.hasPrefix("The text is not valid YAML") {
                return "Before anything can be checked, the file has to be readable as text laid out in keys and values. "
                    + "A bracket, a quote or an indent that does not match stops the reading at that point."
            }
            if what.hasPrefix("The file lists no") {
                return "The list of servers tells a program where your service is. Without it a program has to guess, or someone has to type "
                    + "the address in by hand."
            }
            if what.hasPrefix("This operation has no") {
                return "Without a name of your own, a code generator makes one up from the method and the address. Such names are long "
                    + "and change when the address changes."
            }
            return "Each part of the file takes a certain kind of value. A value of another kind cannot be understood, "
                + "so tools stop reading the part that holds it."
        }
    }
}
