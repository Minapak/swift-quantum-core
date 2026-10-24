# SwiftQuantum Core

Runs offline on the device in your pocket. No server, no laptop, no Python required to run. Exports to OpenQASM and Stim for everything else.

### Clifford (stabilizer) circuits up to 127 qubits on-device. Clifford circuits only.

SwiftQuantum Core is an Apache-2.0 Swift package with three parts:

- **`CliffordSimulator`**: a CHP stabilizer tableau (Aaronson & Gottesman 2004). Runs Clifford circuits with mid-circuit measurement, reset, Pauli noise, detectors and logical observables, and reports detection events.
- **`StateVectorSimulator`**: an exact dense statevector kernel for any gate in the package, small circuits only, running entirely on the device.
- **`Circuit`**: the circuit model, with OpenQASM 2.0 and Stim circuit text import and export.

The code is lifted from the SwiftQuantum IDE app on the App Store, where the same components run in production.

## What this package is and is not

| | |
|---|---|
| **Clifford only for 127 qubits** | Runs Clifford (stabilizer) circuits up to 127 qubits on-device. A circuit with a T, rotation, Toffoli or Fredkin gate is refused by the stabilizer simulator with an error. It never gets an approximate answer. |
| **Measured range, not a cap** | Dense statevector kernel: measured practical range on iPhone ~25 qubits (documented, not enforced). The kernel refuses a circuit only when its statevector would not fit in physical memory. |
| **Simulator** | This is a simulator, not quantum hardware. |
| **Stim is the reference** | Stim is the reference stabilizer simulator; this package targets Swift/on-device, not speed. If you have a laptop and need speed or scale, use Stim. |
| **No decoding** | No QEC decoding is provided by this package. It runs the circuit, records detection events and exports them for PyMatching, Stim's tooling or any other decoder. |
| **No cryptography** | No cryptographic implementation (no FIPS claims). |
| **Pseudo-random** | Simulated randomness is pseudo-random (xoshiro256\*\*, seedable); not a hardware QRNG. |

## Quick start

From a clone:

```bash
swift run -c release ghz127
```

In your own project, add the package:

```swift
.package(url: "https://github.com/Minapak/swift-quantum-core.git", from: "0.1.0")
```

Then:

```swift
import SwiftQuantumCore

var c = Circuit(qubits: 127)
c.h(0)
for q in 1..<127 { c.cnot(0, q) }   // 127-qubit GHZ, all Clifford
let sim = CliffordSimulator()
let result = try sim.run(c, shots: 100)
```

`result.counts` holds exactly two bitstrings: 127 zeros and 127 ones.

## Capabilities

| | Stabilizer `CliffordSimulator` | Exact dense `StateVectorSimulator` |
|---|---|---|
| Gates | I, X, Y, Z, H, S, S†, CNOT, CZ, SWAP | all of those, plus T, RX, RY, RZ, CCX, CSWAP |
| Also | mid-circuit measurement, reset, `X_ERROR`, `Y_ERROR`, `Z_ERROR`, `DEPOLARIZE1`, detectors, observables | measurements at the end only |
| State memory | (2n+1)² bytes: 65,025 bytes at 127 qubits | 16 · 2ⁿ bytes: 512 MB at 25 qubits |
| Measured on iPhone, airplane mode, inside the SwiftQuantum IDE app (2026-07-01) | 127-qubit GHZ: 2,166 ms, 63.5 KB | 25 qubits, non-Clifford: 910 ms, 512 MB |
| Measured on iPhone 13 Pro (iPhone14,2, iOS 27.0.1) with this package, `DeviceReportTests`, release build (2026-10-25) | 127-qubit GHZ, 100 shots: 20.2 ms, 65,025 bytes | 25 qubits, non-Clifford, 100 shots: 3,882 ms, 512 MB |
| Measured on a Mac (Mac17,7, Apple M5 Max) with this package, `capability-report`, release build (2026-10-22) | 127-qubit GHZ, 100 shots: 12.1 ms | 22 qubits, 100 shots: 225 ms |
| Hard-coded limit | none; 127 is the documented measurement | none; refuses only when the statevector exceeds physical memory |

Reproduce the Mac row on your own machine:

```bash
swift run -c release capability-report
```

On an iPhone the same measurements run inside the test suite, through a small host app ([Examples/DeviceHarness](Examples/DeviceHarness/project.yml)), because SwiftPM test bundles cannot run on a device by themselves. The QECirc #1289 memory experiment with noise 0.005 ran 10,000 shots in 569 ms on the iPhone 13 Pro, with a detection fraction of 0.0689.

`Simulator().run(_:shots:)` picks the engine for you: the stabilizer simulator for Clifford-only circuits, the dense kernel for everything else.

## Examples

| Command | Circuit | Engine |
|---|---|---|
| `swift run bell` | Bell pair | stabilizer |
| `swift run -c release ghz127` | 127-qubit GHZ | stabilizer |
| `swift run qft` | 3-qubit QFT of \|101⟩, prints amplitudes and phases | dense |
| `swift run -c release qecirc-surface-memory` | QECirc #1289: rotated surface code d=3 memory experiment with a uniform noise model; writes the noisy circuit as Stim text and the detection events in Stim's `01` format | stabilizer |
| `swift run repetition-memory` | distance-3 repetition code, 3 rounds, X errors, written for this repository; same two output files | stabilizer |

Three QECirc circuits are included in [third_party/qecirc](third_party/qecirc/README.md): rotated surface code d=3 (two syndrome schedules) and d=5. **They are CC BY-SA 4.0, not Apache-2.0**, copied unchanged from QECirc with attribution. All 670 annotated memory experiments in QECirc (commit `8a08057`) import; the 542 with at most 100 qubits run with no detector firing when noiseless (`QECIRC_DIR=… swift test --filter QECircCorpusTests`).

## Detection events and decoders

```swift
var c = Circuit(qubits: 3)
c.xError(0, probability: 0.01)
c.cnot(0, 1); c.cnot(2, 1)
c.measure(1)
c.detector(-1)                 // Stim-style lookback: -1 is the latest measurement
c.measure(0); c.measure(2)
c.observableInclude(0, -1)

let result = try CliffordSimulator().run(c, shots: 10_000, seed: 7)
let events = result.detectionEvents!.formatted01()   // detectors, then observables, one shot per line
let stimText = try StimCircuit.export(c)            // the same circuit for Stim
```

A detection event is a detector whose parity differs from a noiseless reference run. A detector whose parity is not deterministic without noise is refused with an error.

QECirc circuits are noiseless. `circuit.addingUniformNoise(probability:)` adds a simple teaching noise model (`DEPOLARIZE1` after every gate on each of its qubits, `X_ERROR` before measurements and after resets) so a decoder has something to correct.

### Checked against Stim and PyMatching

[`Scripts/verify_with_stim.py`](Scripts/verify_with_stim.py) re-runs an exported circuit in Stim and decodes both sets of events with PyMatching; [`notebooks/decode_with_pymatching.ipynb`](notebooks/decode_with_pymatching.ipynb) is the same check as a notebook, saved with its outputs. Results on 2026-10-23 (Stim 1.16.0, PyMatching 2.4.0), QECirc #1289 with noise p = 0.005:

| | this package | Stim |
|---|---|---|
| detection fraction, 800,000 shots | 0.06956 | 0.06953 |
| raw logical observable flips, 800,000 shots | 0.12254 | 0.12272 |
| logical error rate after PyMatching, 20,000 shots | 0.0216 | 0.0208 |

In the 100,000-shot run every detector's firing rate agreed with Stim's within |z| < 4 (largest 2.75), and the detector correlation matrices differed by at most 0.015.

## Conventions

- **Bit order.** Count keys are the measurement record, entry 0 rightmost. With no explicit measurement every qubit is measured in order, so qubit 0 is the rightmost character (the same as Qiskit counts).
- **Operands.** Controls first, then targets: `cnot(control, target)`, `ccx(c1, c2, target)`, `cswap(control, a, b)`.
- **Detectors and observables** point into the measurement record with negative lookbacks, like Stim's `rec[-k]`.
- **OpenQASM 2.0.** One `qreg`; `measure q[i] -> c[k]` must write classical bits in order. Noise, detectors and observables are written as comments, because OpenQASM 2.0 has no form for them.
- **Stim.** Import unrolls `REPEAT`, rewrites X/Y-basis measurements and resets and `SQRT_*`/`CY` with H, S and S†, and ignores coordinates and `TICK`. Anything else, and every non-Clifford gate on export, is refused with an error. The full mapping is in [docs/STIM_GATE_MAPPING.md](docs/STIM_GATE_MAPPING.md).

## Related tools

- **[Stim](https://github.com/quantumlib/Stim)** is the reference stabilizer simulator. If you need speed, use Stim. This package does not compete with it on speed or scale. It runs the same formalism on the device a learner already carries and hands the circuit back to Stim.
- **[QECirc](https://qecirc.com)** is where QEC circuits are found and shared; this package is where they run in a pocket.
- **Qiskit, Cirq, PennyLane** are the reference Python toolchains, reachable through OpenQASM export.
- **Quirk** was the nearest non-Python on-ramp (browser-based, no longer maintained). A native package runs offline on the device and plugs into Swift Package Manager and Xcode.

## Open core boundary

This repository is the correctness layer of SwiftQuantum: the stabilizer simulator, the exact kernel and the circuit model. The speed layer stays commercial and is not here: a Rust engine, a C++ engine, the cloud offload service, and the apps themselves. Nothing app-specific enters this package: no accounts, billing, backend clients or qubit gates by plan. It documents measured ranges instead of imposing caps.

## Roadmap

**M1, month 1**
- [x] Stabilizer simulator, exact kernel, circuit model with OpenQASM export and import
- [x] Mid-circuit measurement, reset, Pauli noise, detectors, observables, detection-event export
- [x] Backend client code excluded (`Scripts/check-boundary.sh`)
- [x] Test suite: `swift test` (XCTest and Swift Testing), and a CI workflow
- [x] v0.1.0 tag
- [ ] Public repository (private until the export-control record is confirmed)
- [x] The SwiftQuantum IDE app imports this package for its stabilizer and dense statevector runs
- [x] A QECirc surface-code memory circuit runs and exports detection events (macOS and the iOS Simulator)
- [x] The same on a physical iPhone (iPhone 13 Pro, all tests through `Examples/DeviceHarness`)
- [x] A notebook that decodes those events with PyMatching

**M2, months 2 to 3**
- [x] Stim circuit text export and import
- [x] QECirc circuits re-run in Stim with matching statistics (`Scripts/verify_with_stim.py`)
- [ ] The same Stim comparison for every example, run in CI
- [ ] DocC documentation and a "your first stabilizer circuit, on your phone" tutorial
- [ ] Ten or more example circuits, including the QECirc set

**M3, month 4**
- [ ] A metriq-gym task for stabilizer simulation on consumer edge devices
- [x] CI workflow with macOS and iOS Simulator jobs (not yet run on GitHub)
- [ ] CONTRIBUTING guide, code of conduct, good first issues
- [ ] Swift Package Index listing and v1.0.0

## Export control

See [docs/EXPORT_CONTROL.md](docs/EXPORT_CONTROL.md).

## License and citation

Apache License 2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE). To cite, see [CITATION.cff](CITATION.cff).

Need a visual editor or a curriculum on top of this? See SwiftQuantum IDE and QuantumNative on the App Store.

Verified, not certified.
