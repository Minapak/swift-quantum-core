// A rotated surface code memory experiment from QECirc (#1289, distance 3,
// AlphaSyndrome schedule; CC BY-SA 4.0, see third_party/qecirc/README.md),
// run on the stabilizer simulator with a uniform noise model added.
//
// Writes, next to where it runs:
//   qecirc_d3_memory.stim   the noisy circuit as Stim text (re-run it in Stim)
//   qecirc_d3_memory.01     detection events + observable, one shot per line
// It does not decode. Scripts/verify_with_stim.py decodes both the device's
// events and Stim's own with PyMatching.
//
//   swift run -c release qecirc-surface-memory [error-probability] [shots] [circuit.stim]

import Foundation
import SwiftQuantumCore

let args = CommandLine.arguments
let p = args.count > 1 ? Double(args[1]) ?? 0.001 : 0.001
let shots = args.count > 2 ? Int(args[2]) ?? 10_000 : 10_000
let defaultPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("third_party/qecirc/rotated-surface-code-d-3--alphasyndrome-schedule-mwpm.stim").path
let path = args.count > 3 ? args[3] : defaultPath

let noiseless = try StimCircuit.parse(String(contentsOfFile: path, encoding: .utf8))
let circuit = noiseless.addingUniformNoise(probability: p)
let result = try CliffordSimulator().run(circuit, shots: shots, seed: 2026)
guard let events = result.detectionEvents else { fatalError("the QECirc memory circuit declares detectors") }

let flips = events.observableFlips.filter { $0.contains(true) }.count
print("QECirc #1289 · rotated surface code d=3 · \(circuit.qubitCount) qubits · \(circuit.measurementCount) measurements per shot")
print("detectors \(events.detectorCount) · observables \(events.observableCount) · shots \(shots) · uniform noise p \(p)")
print(String(format: "detectors fired: %.4f of all (shot, detector) pairs", events.detectionFraction))
print(String(format: "raw logical observable flipped (undecoded): %.4f", Double(flips) / Double(shots)))
print(String(format: "%.1f ms on the stabilizer simulator", result.elapsedMilliseconds))

try StimCircuit.export(circuit).write(toFile: "qecirc_d3_memory.stim", atomically: true, encoding: .utf8)
try events.formatted01(appendObservables: true).write(toFile: "qecirc_d3_memory.01", atomically: true, encoding: .utf8)
print("wrote qecirc_d3_memory.stim and qecirc_d3_memory.01")
print("no decoding here · Clifford circuits only · pseudo-random sampling")
