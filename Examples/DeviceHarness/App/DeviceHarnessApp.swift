// Minimal host app for running SwiftQuantumCore's tests on a device.
// It also runs a 127-qubit GHZ circuit at launch so a person holding the
// phone sees something happen.

import SwiftUI
import SwiftQuantumCore

@main
struct DeviceHarnessApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var line = "Running a 127-qubit GHZ circuit…"

    var body: some View {
        VStack(spacing: 12) {
            Text("SwiftQuantum Core").font(.headline)
            Text(line).font(.system(.body, design: .monospaced)).multilineTextAlignment(.center)
            Text("Clifford circuits only · simulator, not hardware").font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .task {
            var c = Circuit(qubits: 127)
            c.h(0)
            for q in 1..<127 { c.cnot(0, q) }
            if let r = try? CliffordSimulator().run(c, shots: 100) {
                let zeros = r.counts[String(repeating: "0", count: 127)] ?? 0
                let ones = r.counts[String(repeating: "1", count: 127)] ?? 0
                line = String(format: "all 0 ×%d · all 1 ×%d\n%.1f ms, %d-byte tableau", zeros, ones, r.elapsedMilliseconds, r.stateMemoryBytes)
            }
        }
    }
}
