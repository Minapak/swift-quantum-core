//
//  Circuit.swift
//  SwiftQuantumCore
//
//  The circuit model shared by both simulators and both text formats.
//
//  A circuit is an ordered list of operations on a fixed number of qubits:
//  unitary gates, Z-basis measurements, resets, Pauli noise channels, and two
//  annotations over the measurement record (detectors and logical
//  observables). Measurements append to a measurement record; detectors and
//  observables point into that record, the same way Stim's `rec[-k]` does.
//
//  Operand convention for `.gate(_, qubits:, parameters:)`: controls first,
//  then targets.
//    CNOT  [control, target]          CZ     [a, b]
//    SWAP  [a, b]                     CCX    [control1, control2, target]
//    CSWAP [control, a, b]            others [qubit]
//

import Foundation

// MARK: - Gates

/// Gates understood by the package. Raw values match the SwiftQuantum IDE app.
public enum Gate: String, CaseIterable, Codable, Sendable {
    case identity = "I"
    case pauliX = "X"
    case pauliY = "Y"
    case pauliZ = "Z"
    case hadamard = "H"
    case s = "S"
    case sDagger = "SDG"
    case t = "T"
    case rx = "RX"
    case ry = "RY"
    case rz = "RZ"
    case cnot = "CNOT"
    case cz = "CZ"
    case swap = "SWAP"
    case toffoli = "CCX"
    case fredkin = "CSWAP"

    /// Allowlist of gates the stabilizer simulator can run exactly. Anything
    /// not listed here is non-Clifford and must never reach the tableau:
    /// running it there would return a wrong answer, not an error.
    public var isClifford: Bool {
        switch self {
        case .identity, .pauliX, .pauliY, .pauliZ, .hadamard, .s, .sDagger, .cnot, .cz, .swap:
            return true
        case .t, .rx, .ry, .rz, .toffoli, .fredkin:
            return false
        }
    }

    /// Number of qubit operands.
    public var arity: Int {
        switch self {
        case .cnot, .cz, .swap: return 2
        case .toffoli, .fredkin: return 3
        default: return 1
        }
    }

    /// Number of angle parameters (radians).
    public var parameterCount: Int {
        switch self {
        case .rx, .ry, .rz: return 1
        default: return 0
        }
    }
}

/// Single-qubit Pauli noise channels (Clifford-compatible, stabilizer only).
public enum PauliChannel: String, CaseIterable, Codable, Sendable {
    /// Apply X with probability p.
    case xError = "X_ERROR"
    /// Apply Y with probability p.
    case yError = "Y_ERROR"
    /// Apply Z with probability p.
    case zError = "Z_ERROR"
    /// With probability p apply one of X, Y, Z, chosen uniformly.
    case depolarize1 = "DEPOLARIZE1"
}

// MARK: - Operations

public enum Operation: Equatable, Codable, Sendable {
    case gate(Gate, qubits: [Int], parameters: [Double])
    /// Z-basis measurement. Appends one bit to the measurement record.
    case measure(Int)
    /// Reset to |0⟩.
    case reset(Int)
    case noise(PauliChannel, qubit: Int, probability: Double)
    /// Parity of these measurement-record entries (absolute indices) is
    /// deterministic without noise; a flip of it is a detection event.
    case detector(records: [Int])
    /// Adds these measurement-record entries (absolute indices) to logical
    /// observable `index`.
    case observable(index: Int, records: [Int])

    var isGate: Bool {
        if case .gate = self { return true }
        return false
    }
}

// MARK: - Circuit

public struct Circuit: Equatable, Codable, Sendable {
    public let qubitCount: Int
    public private(set) var operations: [Operation] = []
    /// Number of entries the measurement record will have after a run.
    public private(set) var measurementCount = 0

    public init(qubits: Int) {
        precondition(qubits >= 1, "a circuit needs at least one qubit")
        qubitCount = qubits
    }

    // Decoding re-validates every operation, so malformed JSON is an error
    // here rather than a crash inside a simulator.
    private enum CodingKeys: String, CodingKey { case qubitCount, operations }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let n = try container.decode(Int.self, forKey: .qubitCount)
        guard n >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .qubitCount, in: container,
                                                   debugDescription: "a circuit needs at least one qubit")
        }
        qubitCount = n
        for op in try container.decode([Operation].self, forKey: .operations) {
            try append(op)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(qubitCount, forKey: .qubitCount)
        try container.encode(operations, forKey: .operations)
    }

    // MARK: Appending (validated)

    /// Append an operation, throwing if it is malformed (qubit out of range,
    /// repeated operand, wrong parameter count, probability outside [0, 1],
    /// record index that does not exist yet). Used by the text importers.
    public mutating func append(_ op: Operation) throws {
        if let problem = validate(op) {
            throw CircuitError.invalidOperation(index: operations.count, reason: problem)
        }
        operations.append(op)
        if case .measure = op { measurementCount += 1 }
    }

    /// Builder path: a malformed operation here is a programming error, the
    /// same way an out-of-range array index is.
    private mutating func add(_ op: Operation) {
        do { try append(op) } catch { preconditionFailure("\(error)") }
    }

    private func validate(_ op: Operation) -> String? {
        func inRange(_ q: Int) -> Bool { q >= 0 && q < qubitCount }
        switch op {
        case .gate(let g, let qs, let ps):
            if qs.count != g.arity { return "\(g.rawValue) takes \(g.arity) qubit(s), got \(qs.count)" }
            if !qs.allSatisfy(inRange) { return "\(g.rawValue) qubit out of range 0..<\(qubitCount): \(qs)" }
            if Set(qs).count != qs.count { return "\(g.rawValue) has a repeated qubit: \(qs)" }
            if ps.count != g.parameterCount { return "\(g.rawValue) takes \(g.parameterCount) parameter(s), got \(ps.count)" }
            if !ps.allSatisfy({ $0.isFinite }) { return "\(g.rawValue) parameter is not finite" }
        case .measure(let q), .reset(let q):
            if !inRange(q) { return "qubit \(q) out of range 0..<\(qubitCount)" }
        case .noise(let channel, let q, let p):
            if !inRange(q) { return "qubit \(q) out of range 0..<\(qubitCount)" }
            if !(p >= 0 && p <= 1) { return "\(channel.rawValue) probability \(p) is outside [0, 1]" }
        case .detector(let records):
            if let bad = records.first(where: { $0 < 0 || $0 >= measurementCount }) {
                return "detector refers to measurement \(bad), but only \(measurementCount) exist so far"
            }
        case .observable(let index, let records):
            if index < 0 { return "observable index \(index) is negative" }
            if let bad = records.first(where: { $0 < 0 || $0 >= measurementCount }) {
                return "observable refers to measurement \(bad), but only \(measurementCount) exist so far"
            }
        }
        return nil
    }

    // MARK: Gate builders

    public mutating func i(_ q: Int) { add(.gate(.identity, qubits: [q], parameters: [])) }
    public mutating func x(_ q: Int) { add(.gate(.pauliX, qubits: [q], parameters: [])) }
    public mutating func y(_ q: Int) { add(.gate(.pauliY, qubits: [q], parameters: [])) }
    public mutating func z(_ q: Int) { add(.gate(.pauliZ, qubits: [q], parameters: [])) }
    public mutating func h(_ q: Int) { add(.gate(.hadamard, qubits: [q], parameters: [])) }
    public mutating func s(_ q: Int) { add(.gate(.s, qubits: [q], parameters: [])) }
    public mutating func sdg(_ q: Int) { add(.gate(.sDagger, qubits: [q], parameters: [])) }
    public mutating func t(_ q: Int) { add(.gate(.t, qubits: [q], parameters: [])) }
    public mutating func rx(_ q: Int, theta: Double) { add(.gate(.rx, qubits: [q], parameters: [theta])) }
    public mutating func ry(_ q: Int, theta: Double) { add(.gate(.ry, qubits: [q], parameters: [theta])) }
    public mutating func rz(_ q: Int, theta: Double) { add(.gate(.rz, qubits: [q], parameters: [theta])) }
    public mutating func cnot(_ control: Int, _ target: Int) { add(.gate(.cnot, qubits: [control, target], parameters: [])) }
    public mutating func cz(_ a: Int, _ b: Int) { add(.gate(.cz, qubits: [a, b], parameters: [])) }
    public mutating func swap(_ a: Int, _ b: Int) { add(.gate(.swap, qubits: [a, b], parameters: [])) }
    public mutating func ccx(_ control1: Int, _ control2: Int, _ target: Int) {
        add(.gate(.toffoli, qubits: [control1, control2, target], parameters: []))
    }
    public mutating func cswap(_ control: Int, _ a: Int, _ b: Int) {
        add(.gate(.fredkin, qubits: [control, a, b], parameters: []))
    }

    // MARK: Measurement, reset, noise

    public mutating func measure(_ q: Int) { add(.measure(q)) }
    /// Measure qubits 0, 1, …, n-1 in order.
    public mutating func measureAll() { for q in 0..<qubitCount { add(.measure(q)) } }
    public mutating func reset(_ q: Int) { add(.reset(q)) }
    public mutating func xError(_ q: Int, probability p: Double) { add(.noise(.xError, qubit: q, probability: p)) }
    public mutating func yError(_ q: Int, probability p: Double) { add(.noise(.yError, qubit: q, probability: p)) }
    public mutating func zError(_ q: Int, probability p: Double) { add(.noise(.zError, qubit: q, probability: p)) }
    public mutating func depolarize1(_ q: Int, probability p: Double) { add(.noise(.depolarize1, qubit: q, probability: p)) }

    // MARK: Detectors and observables (Stim-style lookback: -1 is the latest measurement)

    /// Declare a detector over earlier measurements, addressed by lookback
    /// (`-1` = most recent measurement, `-2` = the one before, …).
    public mutating func detector(_ lookback: Int...) { add(.detector(records: absolute(lookback))) }

    /// Include earlier measurements (by lookback) in logical observable `index`.
    public mutating func observableInclude(_ index: Int, _ lookback: Int...) {
        add(.observable(index: index, records: absolute(lookback)))
    }

    private func absolute(_ lookback: [Int]) -> [Int] {
        lookback.map { k in
            precondition(k < 0 && -k <= measurementCount,
                         "lookback \(k) needs \(-k) earlier measurements, circuit has \(measurementCount)")
            return measurementCount + k
        }
    }

    // MARK: Noise model

    /// A copy with a simple uniform circuit-level noise model, for trying
    /// decoders on noiseless circuits (QECirc circuits are noiseless):
    ///   * `DEPOLARIZE1(p)` on every qubit of every gate, after the gate
    ///     (single-qubit depolarizing on each qubit of a two-qubit gate, not
    ///     Stim's two-qubit `DEPOLARIZE2`),
    ///   * `X_ERROR(p)` before every measurement and after every reset.
    /// Identity gates, existing noise, detectors and observables are kept
    /// as they are. This is a teaching model, not a hardware model.
    public func addingUniformNoise(probability p: Double) -> Circuit {
        precondition(p >= 0 && p <= 1, "probability \(p) is outside [0, 1]")
        var out = Circuit(qubits: qubitCount)
        for op in operations {
            switch op {
            case .gate(let g, let qs, _):
                out.add(op)
                if g != .identity { for q in qs { out.add(.noise(.depolarize1, qubit: q, probability: p)) } }
            case .measure(let q):
                out.add(.noise(.xError, qubit: q, probability: p))
                out.add(op)
            case .reset(let q):
                out.add(op)
                out.add(.noise(.xError, qubit: q, probability: p))
            case .noise, .detector, .observable:
                out.add(op)
            }
        }
        return out
    }

    // MARK: Queries

    /// True when every gate is Clifford, so the whole circuit can run on the
    /// stabilizer simulator.
    public var isCliffordOnly: Bool { firstNonClifford == nil }

    /// The first non-Clifford gate and its operation index, if any.
    public var firstNonClifford: (index: Int, gate: Gate)? {
        for (i, op) in operations.enumerated() {
            if case .gate(let g, _, _) = op, !g.isClifford { return (i, g) }
        }
        return nil
    }

    public var gateCount: Int { operations.reduce(0) { $0 + ($1.isGate ? 1 : 0) } }

    public var detectorCount: Int {
        operations.reduce(0) { n, op in
            if case .detector = op { return n + 1 }
            return n
        }
    }

    /// Number of logical observables (highest index + 1).
    public var observableCount: Int {
        operations.reduce(0) { n, op in
            if case .observable(let index, _) = op { return max(n, index + 1) }
            return n
        }
    }

    /// Layered depth of the gates: each gate goes in the earliest layer its
    /// qubits allow.
    public var depth: Int {
        var free = [Int](repeating: 0, count: qubitCount)
        var result = 0
        for case .gate(_, let qs, _) in operations {
            let layer = qs.map { free[$0] }.max() ?? 0
            for q in qs { free[q] = layer + 1 }
            result = max(result, layer + 1)
        }
        return result
    }
}

public enum CircuitError: Error, LocalizedError, Equatable {
    case invalidOperation(index: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidOperation(let index, let reason): return "Operation \(index): \(reason)"
        }
    }
}
