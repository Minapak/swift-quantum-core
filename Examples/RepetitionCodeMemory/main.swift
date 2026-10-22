// Distance-3 bit-flip repetition code, 3 rounds of stabilizer measurement,
// with X errors on the data qubits. Prints detection-event statistics and
// writes two files for the tools that decode:
//   repetition_memory.stim   Stim circuit text (run it again in Stim)
//   repetition_memory.01     detection events + observable, one shot per line
// This package does not decode; PyMatching or Stim's tooling does.
//
// This circuit is written for this repository as a small stand-in. The
// surface-code memory example taken from QECirc will be added once its file
// format and license are confirmed.
//
//   swift run repetition-memory [error-probability] [shots]

import Foundation
import SwiftQuantumCore

let args = CommandLine.arguments
let p = args.count > 1 ? Double(args[1]) ?? 0.05 : 0.05
let shots = args.count > 2 ? Int(args[2]) ?? 10_000 : 10_000
let rounds = 3

// data qubits 0, 2, 4 · measure (ancilla) qubits 1, 3
var c = Circuit(qubits: 5)
for round in 0..<rounds {
    for d in [0, 2, 4] { c.xError(d, probability: p) }
    c.cnot(0, 1); c.cnot(2, 1)
    c.cnot(2, 3); c.cnot(4, 3)
    c.measure(1); c.measure(3)
    c.reset(1); c.reset(3)
    if round == 0 {
        c.detector(-2)
        c.detector(-1)
    } else {
        c.detector(-2, -4)
        c.detector(-1, -3)
    }
}
c.measure(0); c.measure(2); c.measure(4)
c.detector(-3, -2, -5)
c.detector(-2, -1, -4)
c.observableInclude(0, -1)

let result = try CliffordSimulator().run(c, shots: shots, seed: 2026)
guard let events = result.detectionEvents else { fatalError("circuit declares detectors") }

let observableFlips = events.observableFlips.filter { $0[0] }.count
print("qubits \(c.qubitCount) · rounds \(rounds) · detectors \(events.detectorCount) · shots \(shots) · p \(p)")
print(String(format: "detectors fired: %.4f of all (shot, detector) pairs", events.detectionFraction))
print(String(format: "raw logical observable flipped (undecoded): %.4f", Double(observableFlips) / Double(shots)))

try StimCircuit.export(c).write(toFile: "repetition_memory.stim", atomically: true, encoding: .utf8)
try events.formatted01(appendObservables: true).write(toFile: "repetition_memory.01", atomically: true, encoding: .utf8)
print("wrote repetition_memory.stim and repetition_memory.01 (detectors then observable per line)")
print("no decoding here · Clifford circuits only · pseudo-random sampling")
