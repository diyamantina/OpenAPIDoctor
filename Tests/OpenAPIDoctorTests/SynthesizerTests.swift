// SynthesizerTests
//
// Unit tests for the two-pass operationId synthesizer + path-param
// encoding rules. These run at the library level (no YAML mutation,
// no validator round-trip).

import Foundation
import Testing

@testable import OpenAPIDoctor

@Suite("Synthesizer: name + collision rules")
struct SynthesizerTests {

    typealias Scanner = OpenAPIDoctor.Synthesis.Scanner

    // MARK: - synthesizeName

    @Test("Simple no-param path: GET /users → getUsers")
    func simpleNoParam() {
        #expect(Scanner.synthesizeName(method: "get", path: "/users") == "getUsers")
    }

    @Test("Single-param path: GET /users/{id} → getUsersById")
    func singleParam() {
        #expect(Scanner.synthesizeName(method: "get", path: "/users/{id}") == "getUsersById")
    }

    @Test("Multi-param path: POST /accounts/{accountId}/users/{userId} → postAccountsByAccountIdUsersByUserId")
    func multiParam() {
        let n = Scanner.synthesizeName(
            method: "post",
            path: "/accounts/{accountId}/users/{userId}",
        )
        #expect(n == "postAccountsByAccountIdUsersByUserId")
    }

    @Test("Kebab-case param folds to camelCase: GET /items/{item-id} → getItemsByItemId")
    func kebabParam() {
        #expect(Scanner.synthesizeName(method: "get", path: "/items/{item-id}") == "getItemsByItemId")
    }

    @Test("Snake-case param folds to camelCase: GET /items/{item_id} → getItemsByItemId")
    func snakeParam() {
        #expect(Scanner.synthesizeName(method: "get", path: "/items/{item_id}") == "getItemsByItemId")
    }

    @Test("Server URL prefix is NOT part of the synthesized name")
    func noServerInName() {
        // Path `/users` should yield `getUsers` regardless of any
        // `servers: [{url: "/v1"}]` block at the document root --
        // synthesizeName takes only the path templates, no server.
        #expect(Scanner.synthesizeName(method: "get", path: "/users") == "getUsers")
    }

    @Test("Path with version segment: GET /v1/users → getV1Users (version IS part of path templates)")
    func versionInPath() {
        // Per the spec, `/v1/users` is the path template object key.
        // The version is part of the path, NOT a server prefix, so it
        // participates in the synthesised name.
        #expect(Scanner.synthesizeName(method: "get", path: "/v1/users") == "getV1Users")
    }

    @Test("Root path: GET / → get")
    func rootPath() {
        #expect(Scanner.synthesizeName(method: "get", path: "/") == "get")
    }

    @Test("Single-segment path: GET /apod → getApod")
    func singleSegmentPath() {
        #expect(Scanner.synthesizeName(method: "get", path: "/apod") == "getApod")
    }

    @Test("Method casing is normalised to lowercase")
    func methodLowercase() {
        #expect(Scanner.synthesizeName(method: "GET", path: "/users") == "getUsers")
        #expect(Scanner.synthesizeName(method: "Post", path: "/users") == "postUsers")
    }

    // MARK: - scan + two-pass collision resolution

    @Test("Missing-servers detected on a spec without a servers block")
    func detectMissingServers() {
        let yaml = """
        openapi: 3.1.0
        info:
          title: T
          version: 1.0.0
        paths: {}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingServers == true)
        #expect(scan.missingOperationIds.isEmpty)
    }

    @Test("Servers present → not flagged")
    func serversPresentNotFlagged() {
        let yaml = """
        openapi: 3.1.0
        servers:
          - url: /
        info:
          title: T
          version: 1.0.0
        paths: {}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingServers == false)
    }

    @Test("Single missing operationId is surfaced with synthesised name")
    func singleMissingOpId() {
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /apod:
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 1)
        let op = scan.missingOperationIds[0]
        #expect(op.path == "/apod")
        #expect(op.method == "get")
        #expect(op.synthesized == "getApod")
        #expect(op.collisionIndex == 1)
    }

    @Test("Two missing ops with same desired name: second gets _2 suffix")
    func twoMissingSameDesired() {
        // Two paths that synthesise to the same name in this scheme:
        // `/users` and `/Users` both go to `getUsers` (case-folding via
        // first-letter lowering keeps the rest of the segment, but the
        // second segment's letters preserve case in pascalCase; both
        // segments are identical here so both yield `getUsers`).
        // Easier test: two paths with identical synthesised forms via
        // different param-name folds.
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /items/{itemId}:
            get: {responses: {'200': {description: ok}}}
          /items/{item-id}:
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 2)
        #expect(scan.missingOperationIds[0].synthesized == "getItemsByItemId")
        #expect(scan.missingOperationIds[0].collisionIndex == 1)
        #expect(scan.missingOperationIds[1].synthesized == "getItemsByItemId_2")
        #expect(scan.missingOperationIds[1].collisionIndex == 2)
    }

    @Test("Declared operationId is honoured; missing one with the same natural name gets _2")
    func declaredCollides() {
        // First op declares `getUsers`; second op (path `/users`)
        // wants to synthesise `getUsers` too -- must get `_2`.
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /a:
            get: {operationId: getUsers, responses: {'200': {description: ok}}}
          /users:
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 1)
        #expect(scan.missingOperationIds[0].synthesized == "getUsers_2")
        #expect(scan.missingOperationIds[0].collisionIndex == 2)
    }

    @Test("Declared getUsers does NOT block GET /users/{id} → getUsersById (different natural name)")
    func declaredDoesntBlockDifferentNaturalName() {
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /users:
            get: {operationId: getUsers, responses: {'200': {description: ok}}}
          /users/{id}:
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 1)
        #expect(scan.missingOperationIds[0].synthesized == "getUsersById")
        #expect(scan.missingOperationIds[0].collisionIndex == 1)
    }

    @Test("Non-operation keys under a path-item are skipped (parameters, summary, servers, x-*)")
    func nonOperationKeysSkipped() {
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /users:
            summary: just a path item
            description: not an op
            x-internal-tag: foo
            parameters:
              - {in: query, name: q, schema: {type: string}}
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 1)
        #expect(scan.missingOperationIds[0].method == "get")
    }

    @Test("Document order preserved across both paths and methods")
    func documentOrderPreserved() {
        let yaml = """
        openapi: 3.1.0
        servers: [{url: /}]
        info: {title: T, version: 1.0.0}
        paths:
          /z:
            post: {responses: {'200': {description: ok}}}
            get: {responses: {'200': {description: ok}}}
          /a:
            get: {responses: {'200': {description: ok}}}
        """
        let scan = Scanner().scan(yaml: yaml)
        #expect(scan.missingOperationIds.count == 3)
        // /z first (document order), then post + get under /z, then /a
        #expect(scan.missingOperationIds[0].path == "/z")
        #expect(scan.missingOperationIds[0].method == "post")
        #expect(scan.missingOperationIds[1].path == "/z")
        #expect(scan.missingOperationIds[1].method == "get")
        #expect(scan.missingOperationIds[2].path == "/a")
        #expect(scan.missingOperationIds[2].method == "get")
    }
}
