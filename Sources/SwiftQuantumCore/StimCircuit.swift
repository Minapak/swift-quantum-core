//
//  StimCircuit.swift
//  SwiftQuantumCore
//
//  Stim circuit text import and export. Import lets circuits from Stim users
//  and from QECirc run on the device; export sends a circuit back to Stim
//  (the reference stabilizer simulator) so its detection events can be
//  checked there and decoded with PyMatching. The full mapping is in
//  docs/STIM_GATE_MAPPING.md. Unsupported instructions throw with their line
//  number; nothing is dropped silently.
//

import Foundation

public enum StimParseError: Error, LocalizedError, Equatable {
    case unsupported(line: Int, instruction: String)
    case malformed(line: Int, message: String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unsupported(let line, let name):
            return "Stim line \(line): '\(name)' is not supported by this package (see docs/STIM_GATE_MAPPING.md)"
        case .malformed(let line, let message):
            return "Stim line \(line): \(message)"
        case .empty:
            return "No qubits found in Stim circuit"
        }
    }
}

public enum StimExportError: Error, LocalizedError, Equatable {
    /// Stim simulates stabilizer circuits; non-Clifford gates have no Stim form.
    case nonCliffordGate(Gate, operationIndex: Int)

    public var errorDescription: String? {
        switch self {
        case .nonCliffordGate(let g, let i):
            return "Operation \(i): \(g.rawValue) is not a Clifford gate and has no Stim instruction"
        }
    }
}

public enum StimCircuit {

    /// Stim circuit text for `circuit`. Detector and observable record
    /// indices are written as `rec[-k]` lookbacks. A circuit without explicit
    /// measurements gets `M 0 1 … n-1` at the end, matching what the
    /// simulators in this package do with it.
    public static func export(_ circuit: Circuit) throws -> String {
        var lines: [String] = []
        var measured = 0
        func lookback(_ records: [Int]) -> String {
            records.map { "rec[\($0 - measured)]" }.joined(separator: " ")
        }
        for (i, op) in circuit.operations.enumerated() {
            switch op {
            case .gate(let g, let qs, _):
                guard let name = instruction(for: g) else {
                    throw StimExportError.nonCliffordGate(g, operationIndex: i)
                }
                lines.append("\(name) " + qs.map(String.init).joined(separator: " "))
            case .measure(let q):
                lines.append("M \(q)")
                measured += 1
            case .reset(let q):
                lines.append("R \(q)")
            case .noise(let channel, let q, let p):
                lines.append("\(channel.rawValue)(\(OpenQASM.fmt(p))) \(q)")
            case .detector(let records):
                lines.append("DETECTOR " + lookback(records))
            case .observable(let index, let records):
                lines.append("OBSERVABLE_INCLUDE(\(index)) " + lookback(records))
            }
        }
        if circuit.measurementCount == 0 {
            lines.append("M " + (0..<circuit.qubitCount).map(String.init).joined(separator: " "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Stim instruction name for a Clifford gate; nil for non-Clifford gates.
    public static func instruction(for gate: Gate) -> String? {
        switch gate {
        case .identity: return "I"
        case .pauliX: return "X"
        case .pauliY: return "Y"
        case .pauliZ: return "Z"
        case .hadamard: return "H"
        case .s: return "S"
        case .sDagger: return "S_DAG"
        case .cnot: return "CX"
        case .cz: return "CZ"
        case .swap: return "SWAP"
        case .t, .rx, .ry, .rz, .toffoli, .fredkin: return nil
        }
    }
}

// MARK: - Import

extension StimCircuit {

    /// One primitive operation before qubit count is known. Record lookbacks
    /// stay relative until the circuit is built.
    private enum Step {
        case gate(Gate, [Int])
        case measure(Int)
        case reset(Int)
        case noise(PauliChannel, Int, Double)
        case detector([Int])
        case observable(Int, [Int])
    }

    /// Parse Stim circuit text. The qubit count is the highest qubit index
    /// plus one, as in Stim. `REPEAT` blocks are unrolled; X- and Y-basis
    /// measurements and resets, and the `SQRT_*` / `CY` gates, are rewritten
    /// with H, S and S†. Coordinates and `TICK` are layout only and ignored.
    public static func parse(_ text: String) throws -> Circuit {
        var lines: [(number: Int, text: String)] = []
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = Substring(raw)
            if let hash = line.firstIndex(of: "#") { line = line[..<hash] }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "REPEAT 3 {" and "}" may share a line with nothing else; split braces onto their own entries.
            if trimmed.hasSuffix("{") && trimmed.count > 1 {
                lines.append((i + 1, String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)))
                lines.append((i + 1, "{"))
            } else if !trimmed.isEmpty {
                lines.append((i + 1, trimmed))
            }
        }

        var cursor = 0
        let steps = try parseBlock(lines, &cursor, nested: false)
        var maxQubit = -1
        for step in steps {
            switch step {
            case .gate(_, let qs): maxQubit = max(maxQubit, qs.max() ?? -1)
            case .measure(let q), .reset(let q), .noise(_, let q, _): maxQubit = max(maxQubit, q)
            case .detector, .observable: break
            }
        }
        guard maxQubit >= 0 else { throw StimParseError.empty }

        var circuit = Circuit(qubits: maxQubit + 1)
        for step in steps {
            let m = circuit.measurementCount
            switch step {
            case .gate(let g, let qs): try circuit.append(.gate(g, qubits: qs, parameters: []))
            case .measure(let q): try circuit.append(.measure(q))
            case .reset(let q): try circuit.append(.reset(q))
            case .noise(let channel, let q, let p): try circuit.append(.noise(channel, qubit: q, probability: p))
            case .detector(let lookback): try circuit.append(.detector(records: lookback.map { m + $0 }))
            case .observable(let index, let lookback):
                try circuit.append(.observable(index: index, records: lookback.map { m + $0 }))
            }
        }
        return circuit
    }

    private static func parseBlock(_ lines: [(number: Int, text: String)], _ cursor: inout Int, nested: Bool) throws -> [Step] {
        var steps: [Step] = []
        while cursor < lines.count {
            let (no, text) = lines[cursor]
            cursor += 1
            if text == "}" {
                guard nested else { throw StimParseError.malformed(line: no, message: "unmatched '}'") }
                return steps
            }
            let (name, args, targets) = try split(text, line: no)
            if name == "REPEAT" {
                guard args.isEmpty, targets.count == 1, let count = Int(targets[0]), count >= 0 else {
                    throw StimParseError.malformed(line: no, message: "REPEAT needs a non-negative count")
                }
                guard cursor < lines.count, lines[cursor].text == "{" else {
                    throw StimParseError.malformed(line: no, message: "REPEAT needs '{'")
                }
                cursor += 1
                let body = try parseBlock(lines, &cursor, nested: true)
                for _ in 0..<count { steps += body }
                continue
            }
            if text == "{" { throw StimParseError.malformed(line: no, message: "unexpected '{'") }
            steps += try translate(name, args, targets, line: no)
        }
        if nested { throw StimParseError.malformed(line: lines.last?.number ?? 0, message: "missing '}'") }
        return steps
    }

    /// "NAME(a, b) t1 t2" → ("NAME", [a, b], ["t1", "t2"])
    private static func split(_ text: String, line: Int) throws -> (String, [Double], [String]) {
        var rest = Substring(text)
        var name = ""
        while let c = rest.first, c.isLetter || c.isNumber || c == "_" { name.append(c); rest = rest.dropFirst() }
        guard !name.isEmpty else { throw StimParseError.malformed(line: line, message: "cannot parse '\(text.prefix(40))'") }
        var args: [Double] = []
        if rest.first == "(" {
            guard let close = rest.firstIndex(of: ")") else { throw StimParseError.malformed(line: line, message: "missing ')'") }
            let inside = rest[rest.index(after: rest.startIndex)..<close]
            for part in inside.split(separator: ",") {
                guard let v = Double(part.trimmingCharacters(in: .whitespaces)) else {
                    throw StimParseError.malformed(line: line, message: "bad argument '\(part)'")
                }
                args.append(v)
            }
            rest = rest[rest.index(after: close)...]
        }
        let targets = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        return (name.uppercased(), args, targets)
    }

    private static func translate(_ name: String, _ args: [Double], _ targets: [String], line: Int) throws -> [Step] {
        func qubits() throws -> [Int] {
            try targets.map { t in
                if t.hasPrefix("!") { throw StimParseError.unsupported(line: line, instruction: "\(name) with inverted target \(t)") }
                guard let q = Int(t), q >= 0 else { throw StimParseError.malformed(line: line, message: "bad qubit target '\(t)'") }
                return q
            }
        }
        func pairs() throws -> [(Int, Int)] {
            let qs = try qubits()
            guard qs.count % 2 == 0 else { throw StimParseError.malformed(line: line, message: "\(name) needs qubit pairs") }
            return stride(from: 0, to: qs.count, by: 2).map { (qs[$0], qs[$0 + 1]) }
        }
        func records() throws -> [Int] {
            try targets.map { t in
                guard t.hasPrefix("rec[-"), t.hasSuffix("]"), let k = Int(t.dropFirst(4).dropLast()), k < 0 else {
                    throw StimParseError.malformed(line: line, message: "expected rec[-k], got '\(t)'")
                }
                return k
            }
        }
        func noArgs() throws {
            guard args.allSatisfy({ $0 == 0 }) else {
                throw StimParseError.unsupported(line: line, instruction: "\(name)(\(args.map { "\($0)" }.joined(separator: ",")))")
            }
        }
        func single(_ gates: [Gate]) throws -> [Step] {
            try noArgs()
            return try qubits().flatMap { q in gates.map { Step.gate($0, [q]) } }
        }
        func noise(_ channel: PauliChannel) throws -> [Step] {
            guard args.count == 1, args[0] >= 0, args[0] <= 1 else {
                throw StimParseError.malformed(line: line, message: "\(name) needs one probability")
            }
            return try qubits().map { Step.noise(channel, $0, args[0]) }
        }

        switch name {
        case "TICK", "QUBIT_COORDS", "SHIFT_COORDS":
            return []
        case "I": return try single([.identity])
        case "X": return try single([.pauliX])
        case "Y": return try single([.pauliY])
        case "Z": return try single([.pauliZ])
        case "H", "H_XZ": return try single([.hadamard])
        case "S", "SQRT_Z": return try single([.s])
        case "S_DAG", "SQRT_Z_DAG": return try single([.sDagger])
        case "SQRT_X": return try single([.hadamard, .s, .hadamard])           // H·S·H = √X
        case "SQRT_X_DAG": return try single([.hadamard, .sDagger, .hadamard])
        case "SQRT_Y": return try single([.pauliZ, .hadamard])                // √Y ∝ H·Z
        case "SQRT_Y_DAG": return try single([.hadamard, .pauliZ])
        case "CX", "CNOT", "ZCX":
            try noArgs(); return try pairs().map { Step.gate(.cnot, [$0.0, $0.1]) }
        case "CZ", "ZCZ":
            try noArgs(); return try pairs().map { Step.gate(.cz, [$0.0, $0.1]) }
        case "CY", "ZCY":                                                      // CY = S·CX·S† on the target
            try noArgs()
            return try pairs().flatMap { [Step.gate(.sDagger, [$0.1]), .gate(.cnot, [$0.0, $0.1]), .gate(.s, [$0.1])] }
        case "SWAP":
            try noArgs(); return try pairs().map { Step.gate(.swap, [$0.0, $0.1]) }
        case "M", "MZ":
            try noArgs(); return try qubits().map { Step.measure($0) }
        case "MX":
            try noArgs(); return try qubits().flatMap { [Step.gate(.hadamard, [$0]), .measure($0), .gate(.hadamard, [$0])] }
        case "MY":
            try noArgs()
            return try qubits().flatMap { q in
                [Step.gate(.sDagger, [q]), .gate(.hadamard, [q]), .measure(q), .gate(.hadamard, [q]), .gate(.s, [q])]
            }
        case "R", "RZ":
            try noArgs(); return try qubits().map { Step.reset($0) }
        case "RX":
            try noArgs(); return try qubits().flatMap { [Step.reset($0), .gate(.hadamard, [$0])] }
        case "RY":
            try noArgs(); return try qubits().flatMap { [Step.reset($0), .gate(.hadamard, [$0]), .gate(.s, [$0])] }
        case "MR", "MRZ":
            try noArgs(); return try qubits().flatMap { [Step.measure($0), .reset($0)] }
        case "MRX":
            try noArgs()
            return try qubits().flatMap { [Step.gate(.hadamard, [$0]), .measure($0), .reset($0), .gate(.hadamard, [$0])] }
        case "MRY":
            try noArgs()
            return try qubits().flatMap { q in
                [Step.gate(.sDagger, [q]), .gate(.hadamard, [q]), .measure(q), .reset(q), .gate(.hadamard, [q]), .gate(.s, [q])]
            }
        case "X_ERROR": return try noise(.xError)
        case "Y_ERROR": return try noise(.yError)
        case "Z_ERROR": return try noise(.zError)
        case "DEPOLARIZE1": return try noise(.depolarize1)
        case "DETECTOR":
            return [.detector(try records())]        // coordinates (args) ignored
        case "OBSERVABLE_INCLUDE":
            guard args.count == 1, args[0] >= 0, args[0] == args[0].rounded() else {
                throw StimParseError.malformed(line: line, message: "OBSERVABLE_INCLUDE needs one index")
            }
            return [.observable(Int(args[0]), try records())]
        default:
            throw StimParseError.unsupported(line: line, instruction: name)
        }
    }
}
