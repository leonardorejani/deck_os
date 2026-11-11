// swift-tools-version: 6.0
// Núcleo do Deck sem tela: config, HTTP, teclas e fontes. Compila no Mac e no Linux do CI.
import PackageDescription

let package = Package(
    name: "Nucleo",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Nucleo", targets: ["Nucleo"]),
    ],
    targets: [
        // O -enable-testing no release deixa o executável de prova usar @testable import sem quebrar o swift build -c release.
        .target(name: "Nucleo", path: "Nucleo",
                swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .release))]),
        // Só para provar o servidor de verdade no Mac. No Linux o main é vazio.
        // O Info.plist vai dentro do executável (só no macOS): sem NSBluetoothAlwaysUsageDescription o sistema derruba o
        // processo ao primeiro uso do Bluetooth.
        .executableTarget(name: "DeckServidor", dependencies: ["Nucleo"], path: "DeckServidor", exclude: ["Info.plist"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "DeckServidor/Info.plist"],
                                                        .when(platforms: [.macOS]))]),
        .testTarget(name: "NucleoTestes", dependencies: ["Nucleo"], path: "Testes"),
    ]
)
