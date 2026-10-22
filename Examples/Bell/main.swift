// Bell pair: H then CNOT. Only "00" and "11" can appear.
//   swift run bell

import SwiftQuantumCore

var c = Circuit(qubits: 2)
c.h(0)
c.cnot(0, 1)

let result = try CliffordSimulator().run(c, shots: 1000)
for (state, count) in result.counts.sorted(by: { $0.key < $1.key }) {
    print(state, count)
}
print("Clifford circuits only · simulator, not hardware")
