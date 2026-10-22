// swift-tools-version: 5.9
//
// SwiftQuantum Core — stabilizer circuits on the device in your pocket.
//
// Contents (the open layer of SwiftQuantum, lifted from the SwiftQuantum IDE
// app's Core/Engines):
//   * CliffordSimulator  — CHP stabilizer tableau (Aaronson & Gottesman 2004)
//   * StateVectorSimulator — exact dense statevector kernel, no server
//   * Circuit            — circuit model with measurement record, resets,
//                          Pauli noise channels, detectors and observables
//   * OpenQASM 2.0 import/export, Stim circuit text export
//
// Not in this package: backend clients, account or billing code, the Rust and
// C++ engines, cloud offload. Those stay in the commercial apps.

import PackageDescription

let package = Package(
    name: "SwiftQuantumCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "SwiftQuantumCore", targets: ["SwiftQuantumCore"]),
    ],
    targets: [
        .target(name: "SwiftQuantumCore"),
        .testTarget(
            name: "SwiftQuantumCoreTests",
            dependencies: ["SwiftQuantumCore"],
            // QECirc circuits, CC BY-SA 4.0 (see third_party/qecirc/README.md)
            resources: [.copy("Resources/qecirc")]
        ),

        // Example circuits. Each one is `swift run <name>` from a fresh clone.
        .executableTarget(name: "bell", dependencies: ["SwiftQuantumCore"], path: "Examples/Bell"),
        .executableTarget(name: "ghz127", dependencies: ["SwiftQuantumCore"], path: "Examples/GHZ127"),
        .executableTarget(name: "qft", dependencies: ["SwiftQuantumCore"], path: "Examples/QFT"),
        .executableTarget(name: "repetition-memory", dependencies: ["SwiftQuantumCore"], path: "Examples/RepetitionCodeMemory"),
        .executableTarget(name: "qecirc-surface-memory", dependencies: ["SwiftQuantumCore"], path: "Examples/QECircSurfaceMemory"),
        // Reproduces the README capability table on whatever machine runs it.
        .executableTarget(name: "capability-report", dependencies: ["SwiftQuantumCore"], path: "Examples/CapabilityReport"),
    ]
)
