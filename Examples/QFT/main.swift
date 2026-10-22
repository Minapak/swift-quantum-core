// 3-qubit quantum Fourier transform of |101⟩ on the exact dense kernel.
// The QFT is not a Clifford circuit, so it runs on StateVectorSimulator.
//   swift run qft

import Foundation
import SwiftQuantumCore

/// Controlled phase CP(λ) from RZ and CNOT (equal up to a global phase).
func controlledPhase(_ c: inout Circuit, _ lambda: Double, control: Int, target: Int) {
    c.rz(control, theta: lambda / 2)
    c.cnot(control, target)
    c.rz(target, theta: -lambda / 2)
    c.cnot(control, target)
    c.rz(target, theta: lambda / 2)
}

let n = 3
var c = Circuit(qubits: n)
c.x(0)
c.x(2)   // |101⟩ = 5 (qubit 0 is the least significant bit)

for j in stride(from: n - 1, through: 0, by: -1) {
    c.h(j)
    for k in stride(from: j - 1, through: 0, by: -1) {
        controlledPhase(&c, .pi / Double(1 << (j - k)), control: k, target: j)
    }
}
for q in 0..<(n / 2) { c.swap(q, n - 1 - q) }

let amplitudes = try StateVectorSimulator().statevector(c)
// Every amplitude has magnitude 1/√8; the phases step by 2π·5/8 (up to a global phase).
let reference = amplitudes[0].phase
for (i, a) in amplitudes.enumerated() {
    var relative = (a.phase - reference) / (2 * .pi) * 8
    relative = (relative.truncatingRemainder(dividingBy: 8) + 8).truncatingRemainder(dividingBy: 8)
    print(String(format: "|%@⟩  |a| = %.4f   phase = 2π·%.2f/8", String(i, radix: 2).leftPadded(n), a.magnitude, relative))
}
print("exact statevector kernel · simulator, not hardware")

extension String {
    func leftPadded(_ width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
