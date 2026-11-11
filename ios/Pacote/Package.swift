// swift-tools-version: 6.0
// Lógica do app do iPhone sem tela: o canal, a ponte com a página e o fluxo de pareamento.
// Compila no Mac e no Linux do CI. O que usa UIKit e WebKit mora em ios/App.
import PackageDescription

let package = Package(
    name: "DeckCasca",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DeckCasca", targets: ["DeckCasca"]),
    ],
    targets: [
        .target(name: "DeckCasca", path: "Sources/DeckCasca"),
        .testTarget(name: "DeckCascaTests", dependencies: ["DeckCasca"], path: "Tests/DeckCascaTests"),
    ]
)
