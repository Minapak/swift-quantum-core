//
//  StateVectorSimulator.swift
//  SwiftQuantumCore
//
//  Exact dense statevector kernel (lifted from the SwiftQuantum IDE app,
//  Core/Engines/ExactStateVector.swift, build 18). Every gate is implemented;
//  nothing is skipped. Runs entirely on the device.
//
//  Practical range, measured in the SwiftQuantum IDE app on an iPhone in
//  airplane mode (2026-07-01): 25 qubits, non-Clifford, 910 ms, 512 MB
//  (2^25 amplitudes × 16 bytes). That figure is documentation, not a cap:
//  this kernel refuses a circuit only when its statevector would not fit in
//  the machine's physical memory.
//
//  Conventions (shared with CliffordSimulator):
//    * qubit k is bit k of the basis index (little-endian),
//    * probability keys are printed most significant bit first, so qubit 0
//      is the rightmost character.
//

import Foundation

public struct ComplexNumber: Equatable, Codable, Sendable {
    public var real: Double
    public var imag: Double

    public init(real: Double, imag: Double = 0) {
        self.real = real
        self.imag = imag
    }

    public var magnitudeSquared: Double { real * real + imag * imag }
    public var magnitude: Double { magnitudeSquared.squareRoot() }
    public var phase: Double { atan2(imag, real) }
}

public struct StateVectorSimulator: Sendable {
    public init() {}

    /// Bytes for an n-qubit statevector (two `Double`s per amplitude).
    public static func requiredBytes(qubits n: Int) -> Double { Double(16) * pow(2, Double(n)) }

    /// Final amplitudes from |0…0⟩. Measurements are ignored (they are only
    /// allowed at the end); any reset, noise channel or detector throws.
    public func statevector(_ circuit: Circuit) throws -> [ComplexNumber] {
        _ = try terminalMeasurements(circuit)
        let (re, im) = try evolve(circuit)
        return zip(re, im).map { ComplexNumber(real: $0, imag: $1) }
    }

    /// Exact probabilities over all qubits, keyed most significant bit first,
    /// dropping entries below `cutoff`.
    public func probabilities(_ circuit: Circuit, cutoff: Double = 1e-12) throws -> [String: Double] {
        _ = try terminalMeasurements(circuit)
        let (re, im) = try evolve(circuit)
        let n = circuit.qubitCount
        var out: [String: Double] = [:]
        for i in 0..<re.count {
            let p = re[i] * re[i] + im[i] * im[i]
            if p > cutoff { out[Self.key(i, n)] = p }
        }
        return out
    }

    /// Sample `shots` outcomes from the exact distribution.
    public func run(_ circuit: Circuit, shots: Int, seed: UInt64? = nil) throws -> SampleResult {
        guard shots >= 1 else { throw SimulationError.invalidShots(shots) }
        let start = DispatchTime.now()
        let measured = try terminalMeasurements(circuit)
        let (re, im) = try evolve(circuit)
        let dim = re.count

        var cdf = [Double](repeating: 0, count: dim)
        var acc = 0.0
        for i in 0..<dim { acc += re[i] * re[i] + im[i] * im[i]; cdf[i] = acc }
        let total = acc > 0 ? acc : 1

        var rng = Xoshiro256StarStar(seed: seed ?? UInt64.random(in: .min ... .max))
        var counts: [String: Int] = [:]
        var record = [UInt8](repeating: 0, count: measured.count)
        for _ in 0..<shots {
            let r = Double.random(in: 0..<total, using: &rng)
            var lo = 0, hi = dim - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cdf[mid] <= r { lo = mid + 1 } else { hi = mid }
            }
            for (k, q) in measured.enumerated() { record[k] = UInt8((lo >> q) & 1) }
            counts[recordKey(record), default: 0] += 1
        }

        return SampleResult(
            engine: .statevector,
            qubitCount: circuit.qubitCount,
            shots: shots,
            measurementCount: measured.count,
            counts: counts,
            detectionEvents: nil,
            elapsedMilliseconds: elapsedMs(since: start),
            stateMemoryBytes: dim * 16
        )
    }

    // MARK: - Internals

    /// The measured qubits in record order. Measurements must come after the
    /// last gate; with none, every qubit is measured in order.
    private func terminalMeasurements(_ circuit: Circuit) throws -> [Int] {
        var measured: [Int] = []
        for (i, op) in circuit.operations.enumerated() {
            switch op {
            case .gate:
                if !measured.isEmpty {
                    throw SimulationError.unsupportedByStateVector(
                        operationIndex: i,
                        reason: "a gate after a measurement (mid-circuit measurement) needs the stabilizer simulator, Clifford circuits only")
                }
            case .measure(let q):
                measured.append(q)
            case .reset:
                throw SimulationError.unsupportedByStateVector(
                    operationIndex: i, reason: "reset needs the stabilizer simulator, Clifford circuits only")
            case .noise(let channel, _, _):
                throw SimulationError.unsupportedByStateVector(
                    operationIndex: i, reason: "\(channel.rawValue) needs the stabilizer simulator, Clifford circuits only")
            case .detector, .observable:
                throw SimulationError.unsupportedByStateVector(
                    operationIndex: i, reason: "detectors and observables need the stabilizer simulator, Clifford circuits only")
            }
        }
        return measured.isEmpty ? Array(0..<circuit.qubitCount) : measured
    }

    private func evolve(_ circuit: Circuit) throws -> ([Double], [Double]) {
        let n = circuit.qubitCount
        let bytes = Self.requiredBytes(qubits: n)
        let physical = ProcessInfo.processInfo.physicalMemory
        // 2^n must also fit in an Int index; past 48 qubits no machine has the memory anyway.
        if n > 48 || bytes > Double(physical) {
            throw SimulationError.stateVectorTooLarge(qubits: n, requiredBytes: bytes, physicalMemoryBytes: physical)
        }
        let dim = 1 << n
        var re = [Double](repeating: 0, count: dim)
        var im = [Double](repeating: 0, count: dim)
        re[0] = 1
        for case .gate(let g, let qs, let ps) in circuit.operations {
            apply(g, qs, ps, n: n, re: &re, im: &im)
        }
        return (re, im)
    }

    static func key(_ index: Int, _ n: Int) -> String {
        let s = String(index, radix: 2)
        return s.count >= n ? s : String(repeating: "0", count: n - s.count) + s
    }

    // MARK: Gate application

    private typealias M2 = (a: (Double, Double), b: (Double, Double), c: (Double, Double), d: (Double, Double))

    private static let pauliXMatrix: M2 = ((0, 0), (1, 0), (1, 0), (0, 0))
    private static let pauliZMatrix: M2 = ((1, 0), (0, 0), (0, 0), (-1, 0))

    private static func matrix(_ gate: Gate, _ p: Double) -> M2? {
        let s = 1.0 / 2.0.squareRoot()
        switch gate {
        case .identity: return ((1, 0), (0, 0), (0, 0), (1, 0))
        case .pauliX: return pauliXMatrix
        case .pauliY: return ((0, 0), (0, -1), (0, 1), (0, 0))
        case .pauliZ: return pauliZMatrix
        case .hadamard: return ((s, 0), (s, 0), (s, 0), (-s, 0))
        case .s: return ((1, 0), (0, 0), (0, 0), (0, 1))
        case .sDagger: return ((1, 0), (0, 0), (0, 0), (0, -1))
        case .t: return ((1, 0), (0, 0), (0, 0), (cos(.pi / 4), sin(.pi / 4)))
        case .rx: return ((cos(p / 2), 0), (0, -sin(p / 2)), (0, -sin(p / 2)), (cos(p / 2), 0))
        case .ry: return ((cos(p / 2), 0), (-sin(p / 2), 0), (sin(p / 2), 0), (cos(p / 2), 0))
        case .rz: return ((cos(p / 2), -sin(p / 2)), (0, 0), (0, 0), (cos(p / 2), sin(p / 2)))
        case .cnot, .cz, .swap, .toffoli, .fredkin: return nil
        }
    }

    private func apply(_ gate: Gate, _ qs: [Int], _ ps: [Double], n: Int, re: inout [Double], im: inout [Double]) {
        switch gate {
        case .cnot:
            Self.apply2(Self.pauliXMatrix, target: qs[1], controls: [qs[0]], n: n, re: &re, im: &im)
        case .cz:
            Self.apply2(Self.pauliZMatrix, target: qs[1], controls: [qs[0]], n: n, re: &re, im: &im)
        case .swap:
            Self.swap(qs[0], qs[1], controls: [], n: n, re: &re, im: &im)
        case .toffoli:
            Self.apply2(Self.pauliXMatrix, target: qs[2], controls: [qs[0], qs[1]], n: n, re: &re, im: &im)
        case .fredkin:
            Self.swap(qs[1], qs[2], controls: [qs[0]], n: n, re: &re, im: &im)
        default:
            // Circuit validation guarantees arity and parameter count.
            let m = Self.matrix(gate, ps.first ?? 0)!
            Self.apply2(m, target: qs[0], controls: [], n: n, re: &re, im: &im)
        }
    }

    /// Apply 2×2 `m` to `target` on the subspace where all `controls` are 1.
    private static func apply2(_ m: M2, target t: Int, controls: [Int], n: Int, re: inout [Double], im: inout [Double]) {
        let dim = 1 << n
        let tb = 1 << t
        var cmask = 0
        for c in controls { cmask |= 1 << c }
        re.withUnsafeMutableBufferPointer { R in
            im.withUnsafeMutableBufferPointer { I in
                for i in 0..<dim where i & tb == 0 && i & cmask == cmask {
                    let j = i | tb
                    let ar = R[i], ai = I[i], br = R[j], bi = I[j]
                    R[i] = m.a.0 * ar - m.a.1 * ai + m.b.0 * br - m.b.1 * bi
                    I[i] = m.a.0 * ai + m.a.1 * ar + m.b.0 * bi + m.b.1 * br
                    R[j] = m.c.0 * ar - m.c.1 * ai + m.d.0 * br - m.d.1 * bi
                    I[j] = m.c.0 * ai + m.c.1 * ar + m.d.0 * bi + m.d.1 * br
                }
            }
        }
    }

    private static func swap(_ a: Int, _ b: Int, controls: [Int], n: Int, re: inout [Double], im: inout [Double]) {
        let dim = 1 << n
        let ab = 1 << a, bb = 1 << b
        var cmask = 0
        for c in controls { cmask |= 1 << c }
        for i in 0..<dim where i & ab != 0 && i & bb == 0 && i & cmask == cmask {
            let j = (i & ~ab) | bb
            re.swapAt(i, j)
            im.swapAt(i, j)
        }
    }
}

// MARK: - Routing

/// Picks the simulator: the stabilizer tableau for Clifford-only circuits,
/// the exact dense kernel for everything else. Neither one quietly returns a
/// wrong or truncated answer; anything out of range throws.
public struct Simulator: Sendable {
    public init() {}

    public func run(_ circuit: Circuit, shots: Int, seed: UInt64? = nil) throws -> SampleResult {
        if circuit.isCliffordOnly {
            return try CliffordSimulator().run(circuit, shots: shots, seed: seed)
        }
        return try StateVectorSimulator().run(circuit, shots: shots, seed: seed)
    }
}
