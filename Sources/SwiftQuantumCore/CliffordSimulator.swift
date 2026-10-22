//
//  CliffordSimulator.swift
//  SwiftQuantumCore
//
//  On-device Clifford (stabilizer) simulator: CHP tableau.
//  Aaronson & Gottesman, "Improved Simulation of Stabilizer Circuits",
//  Phys. Rev. A 70, 052328 (2004), arXiv:quant-ph/0406196.
//
//  A device cannot hold a 2^n statevector much past ~25 qubits. For circuits
//  made only of Clifford gates (H, S, S†, X, Y, Z, CNOT, CZ, SWAP), plus
//  Z measurements, resets and Pauli noise, the stabilizer formalism stores
//  the state in a (2n+1)×(2n+1) tableau: O(n²) memory, O(n) per single-qubit
//  gate, O(n²) per measurement. At 127 qubits that is about 64 KB, so the run
//  never leaves the device.
//
//  Output is a shot-sampled histogram of the measurement record, not a
//  statevector: a 127-qubit statevector cannot be materialised.
//
//  This package runs circuits and reports detection events. It does not
//  decode them; hand them to PyMatching or Stim's tooling.
//

import Dispatch

// MARK: - Tableau (lifted from the SwiftQuantum IDE app, Core/Engines)

/// CHP tableau. Rows 0..<n are destabilizers, n..<2n stabilizers, row 2n is
/// scratch. Columns 0..<n are X bits, n..<2n Z bits, column 2n the sign bit.
/// One byte per cell (not bit-packed): n = 127 → 255 × 255 ≈ 63.5 KB.
final class CliffordTableau {
    let n: Int
    let w: Int          // row width = 2n + 1
    var buf: [UInt8]    // (2n+1) rows × w bytes, row-major, one contiguous buffer

    init(_ n: Int) {
        self.n = n
        self.w = 2 * n + 1
        buf = [UInt8](repeating: 0, count: w * w)
        for i in 0..<n {
            buf[i * w + i] = 1                // destabilizer i: X_i
            buf[(n + i) * w + (n + i)] = 1    // stabilizer i:   Z_i
        }
    }

    private init(n: Int, w: Int, buf: [UInt8]) { self.n = n; self.w = w; self.buf = buf }
    func clone() -> CliffordTableau { CliffordTableau(n: n, w: w, buf: buf) }

    var byteCount: Int { w * w }

    /// g(x1,z1,x2,z2) from Aaronson–Gottesman: exponent of i in a Pauli product.
    @inline(__always)
    private func gFunc(_ x1: UInt8, _ z1: UInt8, _ x2: UInt8, _ z2: UInt8) -> Int {
        if x1 == 0 && z1 == 0 { return 0 }
        let x2i = Int(x2), z2i = Int(z2)
        if x1 == 1 && z1 == 1 { return z2i - x2i }
        if x1 == 1 && z1 == 0 { return z2i * (2 * x2i - 1) }
        /* x1 = 0, z1 = 1 */ return x2i * (1 - 2 * z2i)
    }

    /// rowsum(h, i): row h := row h · row i (Aaronson–Gottesman Eq. 4).
    func rowsum(_ h: Int, _ i: Int) {
        let hb = h * w, ib = i * w
        var sum = 2 * Int(buf[hb + 2 * n]) + 2 * Int(buf[ib + 2 * n])
        for j in 0..<n {
            sum += gFunc(buf[ib + j], buf[ib + n + j], buf[hb + j], buf[hb + n + j])
        }
        sum = ((sum % 4) + 4) % 4
        buf[hb + 2 * n] = sum == 2 ? 1 : 0
        for j in 0..<(2 * n) { buf[hb + j] ^= buf[ib + j] }
    }

    // MARK: Gates

    func h(_ q: Int) {
        for i in 0..<(2 * n) {
            let b = i * w
            let xi = buf[b + q], zi = buf[b + n + q]
            buf[b + 2 * n] ^= (xi & zi)
            buf[b + q] = zi
            buf[b + n + q] = xi
        }
    }

    func s(_ q: Int) {
        for i in 0..<(2 * n) {
            let b = i * w
            let xi = buf[b + q], zi = buf[b + n + q]
            buf[b + 2 * n] ^= (xi & zi)
            buf[b + n + q] = xi ^ zi
        }
    }

    func cnot(_ c: Int, _ t: Int) {
        for i in 0..<(2 * n) {
            let b = i * w
            let xc = buf[b + c], zc = buf[b + n + c]
            let xt = buf[b + t], zt = buf[b + n + t]
            buf[b + 2 * n] ^= (xc & zt & (xt ^ zc ^ 1))
            buf[b + t] = xt ^ xc
            buf[b + n + c] = zc ^ zt
        }
    }

    func x(_ q: Int) { for i in 0..<(2 * n) { let b = i * w; buf[b + 2 * n] ^= buf[b + n + q] } }
    func z(_ q: Int) { for i in 0..<(2 * n) { let b = i * w; buf[b + 2 * n] ^= buf[b + q] } }
    func y(_ q: Int) { for i in 0..<(2 * n) { let b = i * w; buf[b + 2 * n] ^= (buf[b + q] ^ buf[b + n + q]) } }
    func sdg(_ q: Int) { s(q); s(q); s(q) }
    func cz(_ a: Int, _ b: Int) { h(b); cnot(a, b); h(b) }
    func swap(_ a: Int, _ b: Int) { cnot(a, b); cnot(b, a); cnot(a, b) }

    func apply(_ gate: Gate, _ qs: [Int]) {
        switch gate {
        case .identity: break
        case .pauliX: x(qs[0])
        case .pauliY: y(qs[0])
        case .pauliZ: z(qs[0])
        case .hadamard: h(qs[0])
        case .s: s(qs[0])
        case .sDagger: sdg(qs[0])
        case .cnot: cnot(qs[0], qs[1])
        case .cz: cz(qs[0], qs[1])
        case .swap: swap(qs[0], qs[1])
        case .t, .rx, .ry, .rz, .toffoli, .fredkin:
            preconditionFailure("non-Clifford gate \(gate.rawValue) reached the tableau")
        }
    }

    // MARK: Measurement

    /// Measure qubit `a` in the Z basis. `randomBit` decides a random outcome
    /// (a seeded generator for samples, a fixed value for reference runs).
    /// Returns the outcome and whether it was random.
    func measure(_ a: Int, randomBit: () -> UInt8) -> (bit: UInt8, random: Bool) {
        var p = -1
        for i in n..<(2 * n) where buf[i * w + a] == 1 { p = i; break }

        if p != -1 {
            for i in 0..<(2 * n) where i != p && buf[i * w + a] == 1 { rowsum(i, p) }
            // Destabilizer row (p - n) := stabilizer row p.
            let src = p * w, dst = (p - n) * w
            for j in 0..<w { buf[dst + j] = buf[src + j] }
            // Stabilizer row p := ±Z_a with a random sign.
            let pb = p * w
            for j in 0..<w { buf[pb + j] = 0 }
            let bit = randomBit() & 1
            buf[pb + 2 * n] = bit
            buf[pb + n + a] = 1
            return (bit, true)
        }

        // Deterministic outcome, accumulated in scratch row 2n.
        let sb = (2 * n) * w
        for j in 0..<w { buf[sb + j] = 0 }
        for i in 0..<n where buf[i * w + a] == 1 { rowsum(2 * n, n + i) }
        return (buf[sb + 2 * n], false)
    }
}

// MARK: - Simulator

/// Runs Clifford circuits on the stabilizer tableau. Throws on any
/// non-Clifford gate instead of returning a wrong answer.
///
/// Measured in the SwiftQuantum IDE app on an iPhone in airplane mode
/// (2026-07-01): a 127-qubit GHZ circuit in 2,166 ms with a 63.5 KB tableau.
/// 127 is the documented measurement, not a limit: the simulator accepts any
/// qubit count, and per-shot cost grows roughly as n³ when every qubit is
/// measured.
public struct CliffordSimulator: Sendable {
    public init() {}

    public func run(_ circuit: Circuit, shots: Int, seed: UInt64? = nil) throws -> SampleResult {
        guard shots >= 1 else { throw SimulationError.invalidShots(shots) }
        if let bad = circuit.firstNonClifford {
            throw SimulationError.nonCliffordGate(bad.gate, operationIndex: bad.index)
        }
        let start = DispatchTime.now()
        let n = circuit.qubitCount

        // No explicit measurement means "measure every qubit at the end".
        var ops = circuit.operations
        let implicitMeasurement = circuit.measurementCount == 0
        if implicitMeasurement { for q in 0..<n { ops.append(.measure(q)) } }
        let measurementCount = implicitMeasurement ? n : circuit.measurementCount

        // Gates before the first measurement, reset or noise channel are the
        // same for every shot: apply them once.
        let prefixEnd = ops.firstIndex { !$0.isGate } ?? ops.count
        let base = CliffordTableau(n)
        for case .gate(let g, let qs, _) in ops[..<prefixEnd] { base.apply(g, qs) }
        let tail = Array(ops[prefixEnd...])

        let detectorCount = circuit.detectorCount
        let observableCount = circuit.observableCount
        var rng = Xoshiro256StarStar(seed: seed ?? UInt64.random(in: .min ... .max))

        // Reference parities: run without noise, once with every random
        // outcome forced to 0 and once forced to 1. A detector whose parity
        // differs between the two is not deterministic, and its "events"
        // would be meaningless, so refuse. (Best-effort: it catches a detector
        // that depends on an odd number of random outcomes.)
        var reference = Shot(record: [], detectors: [], observables: [])
        if detectorCount > 0 || observableCount > 0 {
            let r0 = Self.execute(base, tail, measurementCount, detectorCount, observableCount,
                                  noisy: false, randomBit: { 0 }, rng: &rng)
            let r1 = Self.execute(base, tail, measurementCount, detectorCount, observableCount,
                                  noisy: false, randomBit: { 1 }, rng: &rng)
            if let d = r0.detectors.indices.first(where: { r0.detectors[$0] != r1.detectors[$0] }) {
                throw SimulationError.nonDeterministicDetector(d)
            }
            if let o = r0.observables.indices.first(where: { r0.observables[$0] != r1.observables[$0] }) {
                throw SimulationError.nonDeterministicObservable(o)
            }
            reference = r0
        }

        var counts: [String: Int] = [:]
        var detectorFlips: [[Bool]] = []
        var observableFlips: [[Bool]] = []
        if detectorCount > 0 { detectorFlips.reserveCapacity(shots) }
        if observableCount > 0 { observableFlips.reserveCapacity(shots) }

        for _ in 0..<shots {
            let shot = Self.execute(base, tail, measurementCount, detectorCount, observableCount,
                                    noisy: true, randomBit: nil, rng: &rng)
            counts[recordKey(shot.record), default: 0] += 1
            if detectorCount > 0 {
                detectorFlips.append(zip(shot.detectors, reference.detectors).map { $0 != $1 })
            }
            if observableCount > 0 {
                observableFlips.append(zip(shot.observables, reference.observables).map { $0 != $1 })
            }
        }

        let events: DetectionEvents?
        if detectorCount > 0 || observableCount > 0 {
            events = DetectionEvents(detectorCount: detectorCount, observableCount: observableCount,
                                     detectorFlips: detectorFlips, observableFlips: observableFlips)
        } else {
            events = nil
        }

        return SampleResult(
            engine: .stabilizer,
            qubitCount: n,
            shots: shots,
            measurementCount: measurementCount,
            counts: counts,
            detectionEvents: events,
            elapsedMilliseconds: elapsedMs(since: start),
            stateMemoryBytes: base.byteCount
        )
    }

    // MARK: One shot

    private struct Shot {
        var record: [UInt8]
        var detectors: [UInt8]
        var observables: [UInt8]
    }

    /// Run the non-prefix part of the circuit once. `randomBit == nil` draws
    /// random outcomes and noise from `rng`; otherwise outcomes are forced and
    /// noise is skipped when `noisy` is false.
    private static func execute(
        _ base: CliffordTableau,
        _ tail: [Operation],
        _ measurementCount: Int,
        _ detectorCount: Int,
        _ observableCount: Int,
        noisy: Bool,
        randomBit: (() -> UInt8)?,
        rng: inout Xoshiro256StarStar
    ) -> Shot {
        let t = base.clone()
        var shot = Shot(record: [], detectors: [], observables: [UInt8](repeating: 0, count: observableCount))
        shot.record.reserveCapacity(measurementCount)
        shot.detectors.reserveCapacity(detectorCount)

        func draw(_ rng: inout Xoshiro256StarStar) -> UInt8 { UInt8(truncatingIfNeeded: rng.next() >> 63) }

        for op in tail {
            switch op {
            case .gate(let g, let qs, _):
                t.apply(g, qs)
            case .measure(let q):
                let bit: UInt8
                if let forced = randomBit { bit = t.measure(q, randomBit: forced).bit }
                else { bit = t.measure(q, randomBit: { draw(&rng) }).bit }
                shot.record.append(bit)
            case .reset(let q):
                let bit: UInt8
                if let forced = randomBit { bit = t.measure(q, randomBit: forced).bit }
                else { bit = t.measure(q, randomBit: { draw(&rng) }).bit }
                if bit == 1 { t.x(q) }
            case .noise(let channel, let q, let p):
                guard noisy, p > 0, Double.random(in: 0..<1, using: &rng) < p else { continue }
                switch channel {
                case .xError: t.x(q)
                case .yError: t.y(q)
                case .zError: t.z(q)
                case .depolarize1:
                    switch Int.random(in: 0..<3, using: &rng) {
                    case 0: t.x(q)
                    case 1: t.y(q)
                    default: t.z(q)
                    }
                }
            case .detector(let records):
                shot.detectors.append(records.reduce(0) { $0 ^ shot.record[$1] })
            case .observable(let index, let records):
                shot.observables[index] ^= records.reduce(0) { $0 ^ shot.record[$1] }
            }
        }
        return shot
    }
}

// MARK: - Shared helpers

/// Measurement record as a bitstring: record entry 0 is the RIGHTMOST
/// character. When every qubit is measured in order 0…n-1 this is the usual
/// convention (qubit 0 = least significant bit), the same as the dense kernel
/// and Qiskit's counts.
func recordKey(_ record: [UInt8]) -> String {
    String(record.reversed().map { $0 == 1 ? Character("1") : Character("0") })
}

func elapsedMs(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}
