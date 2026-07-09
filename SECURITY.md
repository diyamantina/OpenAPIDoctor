# Security Policy

## Reporting a vulnerability

If you believe you have found a security issue in OpenAPIDoctor, please report it
privately. Do not open a public issue for security problems.

Email **mihaelamj@gmail.com** with:

- A description of the issue and its impact.
- Steps to reproduce, or a proof of concept.
- The affected version or commit.

You can expect an acknowledgement within a few days. Once the issue is confirmed,
a fix will be prepared and a release cut, after which the issue can be disclosed
publicly with credit to the reporter if desired.

## Supported versions

Security fixes are applied to the latest released version and to the `main`
branch. Older versions are not maintained; upgrade to the latest release to
receive fixes.

## Scope

OpenAPIDoctor parses OpenAPI 3.x documents and rewrites them during `--fix`.
Reports about parsing untrusted spec files (for example, an input that causes a
crash, an unbounded resource consumption, or a path-traversal write during
in-place repair) are in scope. The library and CLI depend on OpenAPIKit, Yams,
and Stitcher; vulnerabilities in those dependencies should be reported to their
respective maintainers, though a heads-up here is welcome.
