//
//  SampleResult.swift
//  SwiftQuantumCore
//

import Foundation

/// Result of sampling a circuit.
public struct SampleResult: Sendable {
    public enum Engine: String, Sendable {
        /// CHP stabilizer tableau (Clifford circuits only).
        case stabilizer
        /// Exact dense statevector kernel.
        case statevector
    }

    public let engine: Engine
    public let qubitCount: Int
    public let shots: Int
    /// Length of the measurement record of one shot.
    public let measurementCount: Int
    /// Shot counts keyed by measurement record. Record entry 0 is the
    /// rightmost character; with no explicit measurements every qubit is
    /// measured in order, so qubit 0 is the rightmost character.
    public let counts: [String: Int]
    /// Detector and observable flips per shot, when the circuit declares any.
    public let detectionEvents: DetectionEvents?
    public let elapsedMilliseconds: Double
    /// Bytes held by the simulator state (tableau or statevector).
    public let stateMemoryBytes: Int

    /// Relative frequencies of `counts`.
    public var probabilities: [String: Double] {
        let total = Double(shots)
        return counts.mapValues { Double($0) / total }
    }
}

/// Detection events: for each shot, which detectors (and observables) flipped
/// relative to a noiseless reference run. This package does not decode them.
public struct DetectionEvents: Sendable, Equatable {
    public let detectorCount: Int
    public let observableCount: Int
    /// `detectorFlips[shot][detector]`
    public let detectorFlips: [[Bool]]
    /// `observableFlips[shot][observable]`
    public let observableFlips: [[Bool]]

    /// Fraction of (shot, detector) pairs that fired.
    public var detectionFraction: Double {
        let total = detectorFlips.count * detectorCount
        guard total > 0 else { return 0 }
        let fired = detectorFlips.reduce(0) { $0 + $1.reduce(0) { $0 + ($1 ? 1 : 0) } }
        return Double(fired) / Double(total)
    }

    /// One line per shot of `0`/`1` characters: detectors in declaration
    /// order, then (optionally) observables. This is the layout Stim writes
    /// for `stim detect --out_format=01 --append_observables`, so PyMatching
    /// and Stim tooling can read it directly.
    public func formatted01(appendObservables: Bool = true) -> String {
        var out = ""
        for (i, row) in detectorFlips.enumerated() {
            out += String(row.map { $0 ? Character("1") : Character("0") })
            if appendObservables, i < observableFlips.count {
                out += String(observableFlips[i].map { $0 ? Character("1") : Character("0") })
            }
            out += "\n"
        }
        return out
    }
}

public enum SimulationError: Error, LocalizedError, Equatable {
    case invalidShots(Int)
    /// The stabilizer simulator only runs Clifford gates.
    case nonCliffordGate(Gate, operationIndex: Int)
    /// The dense kernel runs unitary gates followed by terminal measurements.
    /// Mid-circuit measurement, reset, noise channels and detectors need the
    /// stabilizer simulator (Clifford circuits only).
    case unsupportedByStateVector(operationIndex: Int, reason: String)
    /// The statevector would not fit in this machine's physical memory.
    case stateVectorTooLarge(qubits: Int, requiredBytes: Double, physicalMemoryBytes: UInt64)
    case nonDeterministicDetector(Int)
    case nonDeterministicObservable(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidShots(let s):
            return "shots must be at least 1 (got \(s))"
        case .nonCliffordGate(let g, let i):
            return "Operation \(i): \(g.rawValue) is not a Clifford gate; the stabilizer simulator runs Clifford circuits only"
        case .unsupportedByStateVector(let i, let reason):
            return "Operation \(i): \(reason)"
        case .stateVectorTooLarge(let n, let bytes, let mem):
            return String(format: "A %d-qubit statevector needs %.3g bytes; this machine has %llu bytes of physical memory",
                          n, bytes, mem)
        case .nonDeterministicDetector(let d):
            return "Detector \(d) does not have a deterministic parity without noise"
        case .nonDeterministicObservable(let o):
            return "Observable \(o) does not have a deterministic parity without noise"
        }
    }
}

// MARK: - Pseudo-random generator

/// xoshiro256** (Blackman & Vigna), seeded through SplitMix64. Pseudo-random:
/// reproducible from a seed, and not a source of quantum randomness.
struct Xoshiro256StarStar: RandomNumberGenerator {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    init(seed: UInt64) {
        var z = seed
        func splitMix() -> UInt64 {
            z &+= 0x9E37_79B9_7F4A_7C15
            var x = z
            x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
            return x ^ (x >> 31)
        }
        s = (splitMix(), splitMix(), splitMix(), splitMix())
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

    mutating func next() -> UInt64 {
        let result = Self.rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = Self.rotl(s.3, 45)
        return result
    }
}
