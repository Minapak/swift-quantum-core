// 127-qubit GHZ state on the stabilizer simulator. Every gate is Clifford,
// so the result is exactly two kinds of bitstring: all 0s or all 1s.
//   swift run -c release ghz127

import SwiftQuantumCore

var c = Circuit(qubits: 127)
c.h(0)
for q in 1..<127 { c.cnot(0, q) }   // 127-qubit GHZ, all Clifford
let sim = CliffordSimulator()
let result = try sim.run(c, shots: 100)

for (state, count) in result.counts.sorted(by: { $0.key < $1.key }) {
    let kind = state.allSatisfy { $0 == "0" } ? "all 0" : state.allSatisfy { $0 == "1" } ? "all 1" : "other"
    print("\(kind) ×\(count)  \(state.prefix(12))…")
}
print("tableau \(result.stateMemoryBytes) bytes, \(String(format: "%.1f", result.elapsedMilliseconds)) ms")
print("Clifford circuits only · simulator, not hardware")
