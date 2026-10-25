# Changelog

## Unreleased

- `Examples/DeviceHarness`: a small iOS host app (xcodegen) that runs the whole
  test suite on a physical iPhone or iPad, since SwiftPM test bundles cannot
  run on a device by themselves. Verified on iPhone 13 Pro, iOS 27.0.1,
  Release build (2026-10-25); measurements are in the README.
- `ReadmeSnippetTests` skips the README comparison on a device, where source
  files are not available.

## 0.1.0 — 2026-10-23

Lifted from the SwiftQuantum IDE app (`Core/Engines`): the CHP stabilizer
tableau, the build 18 exact statevector kernel, and the OpenQASM 2.0
exporter and importer. Backend clients, account and billing code, the Rust and
C++ engines and the server offload policy were left out.

Added in the package:

- `Circuit` with a measurement record: mid-circuit measurement, reset,
  `X_ERROR`, `Z_ERROR`, `DEPOLARIZE1`, detectors and observables
  (Stim-style `rec[-k]` lookbacks).
- Detection events relative to a noiseless reference run, exported in Stim's
  `01` layout. A detector with a non-deterministic parity is refused.
- Stim circuit text export and import (REPEAT unrolling; X/Y-basis
  measurement and reset, SQRT_X/SQRT_Y and CY rewritten with H, S, S†).
- `Y_ERROR` and `Circuit.addingUniformNoise(probability:)`.
- Three QECirc surface-code circuits (CC BY-SA 4.0, `third_party/qecirc`),
  the `qecirc-surface-memory` example, an opt-in corpus test over all of
  QECirc, `Scripts/verify_with_stim.py` and a PyMatching notebook.
- Seedable xoshiro256\*\* sampling.
- The dense kernel has no qubit cap. It refuses a circuit only when the
  statevector would not fit in physical memory. (The app caps it at 25 qubits
  as a product policy.)
- `S†` gate, OpenQASM `sdg`, `reset` and per-qubit `measure`.
- Examples: Bell, 127-qubit GHZ, 3-qubit QFT, repetition-code memory, and a
  capability report that reproduces the README table.
