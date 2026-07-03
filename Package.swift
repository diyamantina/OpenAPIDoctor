// swift-tools-version:5.9

import PackageDescription

/// ---------- Dependencies ----------
let deps: [Package.Dependency] = {
    let openAPIKitDep = Package.Dependency.package(
        url: "https://github.com/mattpolzin/OpenAPIKit",
        from: "3.0.0"
    )
    let pureYAMLDep = Package.Dependency.package(
        url: "https://codeberg.org/Mihaela/PureYAML.git",
        from: "0.1.4"
    )
    let stitcherDep = Package.Dependency.package(
        url: "https://codeberg.org/Mihaela/Stitcher",
        from: "2.0.1"
    )
    let doccPluginDep = Package.Dependency.package(
        url: "https://github.com/apple/swift-docc-plugin",
        from: "1.4.3"
    )

    return [
        openAPIKitDep,
        pureYAMLDep,
        stitcherDep,
        doccPluginDep,
    ]
}()

/// ---------- Products ----------
let products: [Product] = {
    let libraryProduct = Product.library(
        name: "OpenAPIDoctor",
        targets: ["OpenAPIDoctor"]
    )
    let executableProduct = Product.executable(
        name: "openapi-doctor",
        targets: ["openapi-doctor"]
    )

    return [
        libraryProduct,
        executableProduct,
    ]
}()

/// ---------- Targets ----------
let targets: [Target] = {
    // ---------- Library ----------
    let libraryTarget = Target.target(
        name: "OpenAPIDoctor",
        dependencies: [
            .product(name: "OpenAPIKit", package: "OpenAPIKit"),
            .product(name: "OpenAPIKit30", package: "OpenAPIKit"),
            .product(name: "PureYAML", package: "PureYAML"),
            .product(name: "Stitcher", package: "Stitcher"),
        ]
    )

    // ---------- Executable ----------
    let executableTarget = Target.executableTarget(
        name: "openapi-doctor",
        dependencies: [
            "OpenAPIDoctor",
        ]
    )

    // ---------- Documentation ----------
    let documentationTarget = Target.target(
        name: "OpenAPIDoctorDocumentation",
        dependencies: [
            "OpenAPIDoctor",
        ]
    )

    // ---------- Tests ----------
    let libraryTestsTarget = Target.testTarget(
        name: "OpenAPIDoctorTests",
        dependencies: [
            "OpenAPIDoctor",
        ],
        resources: [
            .copy("Fixtures"),
        ]
    )

    return [
        libraryTarget,
        executableTarget,
        documentationTarget,
        libraryTestsTarget,
    ]
}()

let package = Package(
    name: "OpenAPIDoctor",
    platforms: [
        .macOS(.v13),
    ],
    products: products,
    dependencies: deps,
    targets: targets
)
