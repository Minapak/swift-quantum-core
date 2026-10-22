//
//  OpenQASM.swift
//  SwiftQuantumCore
//
//  OpenQASM 2.0 export and import (lifted from the SwiftQuantum IDE app,
//  Core/Engines/OpenQASM.swift, build 18). One single-register subset, read
//  and written by the same code. Unsupported statements throw with their
//  statement number; nothing is dropped silently.
//

import Foundation

public enum OpenQASMError: Error, LocalizedError, Equatable {
    case parse(statement: Int, message: String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .parse(let statement, let message): return "QASM statement \(statement): \(message)"
        case .empty: return "No qreg declaration or gates found"
        }
    }
}

public enum OpenQASM {

    // MARK: Export

    /// OpenQASM 2.0 text for `circuit`. Noise channels, detectors and
    /// observables have no OpenQASM 2.0 form; they are written as comments
    /// (use `StimCircuit.export` to keep them).
    public static func export(_ circuit: Circuit) -> String {
        let n = circuit.qubitCount
        let cbits = circuit.measurementCount == 0 ? n : circuit.measurementCount
        var out = "OPENQASM 2.0;\ninclude \"qelib1.inc\";\n\n"
        out += "qreg q[\(n)];\ncreg c[\(cbits)];\n\n"
        var record = 0
        for op in circuit.operations {
            switch op {
            case .gate(let g, let qs, let ps):
                out += line(g, qs, ps) + "\n"
            case .measure(let q):
                out += "measure \(qref(q)) -> c[\(record)];\n"
                record += 1
            case .reset(let q):
                out += "reset \(qref(q));\n"
            case .noise(let channel, let q, let p):
                out += "// \(channel.rawValue)(\(fmt(p))) \(qref(q)); not representable in OpenQASM 2.0\n"
            case .detector(let records):
                out += "// DETECTOR \(records.map { "c[\($0)]" }.joined(separator: " ")); not representable in OpenQASM 2.0\n"
            case .observable(let index, let records):
                out += "// OBSERVABLE_INCLUDE(\(index)) \(records.map { "c[\($0)]" }.joined(separator: " ")); not representable in OpenQASM 2.0\n"
            }
        }
        if circuit.measurementCount == 0 { out += "\nmeasure q -> c;\n" }
        return out
    }

    private static func qref(_ i: Int) -> String { "q[\(i)]" }

    static func fmt(_ x: Double) -> String {
        var s = String(format: "%.15g", x)
        if s == "-0" { s = "0" }
        return s
    }

    private static func line(_ g: Gate, _ qs: [Int], _ ps: [Double]) -> String {
        let ops = qs.map(qref).joined(separator: ",")
        let p = ps.first ?? 0
        switch g {
        case .identity: return "id \(ops);"
        case .pauliX: return "x \(ops);"
        case .pauliY: return "y \(ops);"
        case .pauliZ: return "z \(ops);"
        case .hadamard: return "h \(ops);"
        case .s: return "s \(ops);"
        case .sDagger: return "sdg \(ops);"
        case .t: return "t \(ops);"
        case .rx: return "rx(\(fmt(p))) \(ops);"
        case .ry: return "ry(\(fmt(p))) \(ops);"
        case .rz: return "rz(\(fmt(p))) \(ops);"
        case .cnot: return "cx \(ops);"
        case .cz: return "cz \(ops);"
        case .swap: return "swap \(ops);"
        case .toffoli: return "ccx \(ops);"
        case .fredkin: return "cswap \(ops);"
        }
    }

    // MARK: Import

    /// Parse the OpenQASM 2.0 subset this package can represent: one `qreg`,
    /// the gates in `Gate`, `measure`, `reset`, and `barrier` (ignored).
    /// Measurements become entries of the measurement record, so classical
    /// bits must be written in order: c[0], c[1], …
    public static func parse(_ text: String) throws -> Circuit {
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                if let r = line.range(of: "//") { return line[..<r.lowerBound] }
                return line
            }
            .joined(separator: "\n")
        let statements = cleaned.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Pass 1: register size (gates may only follow a qreg).
        var numQubits = 0
        var sawQreg = false
        for (idx, stmt) in statements.enumerated() where stmt.lowercased().hasPrefix("qreg") {
            guard !sawQreg else {
                throw OpenQASMError.parse(statement: idx + 1, message: "more than one qreg is not supported")
            }
            guard let n = firstIndex(in: stmt), n >= 1 else {
                throw OpenQASMError.parse(statement: idx + 1, message: "bad qreg")
            }
            numQubits = n
            sawQreg = true
        }
        guard sawQreg else { throw OpenQASMError.empty }

        var circuit = Circuit(qubits: numQubits)
        for (idx, stmt) in statements.enumerated() {
            if stmt.isEmpty { continue }
            let lower = stmt.lowercased()
            let no = idx + 1
            if lower.hasPrefix("openqasm") || lower.hasPrefix("include") || lower.hasPrefix("creg")
                || lower.hasPrefix("barrier") || lower.hasPrefix("qreg") {
                continue
            }
            do {
                if lower.hasPrefix("measure") {
                    try parseMeasure(stmt, into: &circuit, statement: no)
                    continue
                }
                if lower.hasPrefix("reset") {
                    let qs = try operands(String(stmt.dropFirst("reset".count)), statement: no)
                    guard qs.count == 1 else { throw OpenQASMError.parse(statement: no, message: "reset takes one qubit") }
                    try circuit.append(.reset(qs[0]))
                    continue
                }
                let (name, params, operandText) = try splitGate(stmt, statement: no)
                let qs = try operands(operandText, statement: no)
                let gate: Gate
                switch (name, qs.count) {
                case ("id", 1), ("i", 1): gate = .identity
                case ("x", 1): gate = .pauliX
                case ("y", 1): gate = .pauliY
                case ("z", 1): gate = .pauliZ
                case ("h", 1): gate = .hadamard
                case ("s", 1): gate = .s
                case ("sdg", 1): gate = .sDagger
                case ("t", 1): gate = .t
                case ("rx", 1): gate = .rx
                case ("ry", 1): gate = .ry
                case ("rz", 1): gate = .rz
                case ("cx", 2), ("cnot", 2): gate = .cnot
                case ("cz", 2): gate = .cz
                case ("swap", 2): gate = .swap
                case ("ccx", 3): gate = .toffoli
                case ("cswap", 3): gate = .fredkin
                default:
                    throw OpenQASMError.parse(statement: no, message: "unsupported gate '\(name)' with \(qs.count) operand(s)")
                }
                var ps: [Double] = []
                if gate.parameterCount == 1 {
                    guard let angle = params, !angle.contains(",") else {
                        throw OpenQASMError.parse(statement: no, message: "\(name) needs one angle")
                    }
                    ps = [try evalAngle(angle, statement: no)]
                } else if params != nil {
                    throw OpenQASMError.parse(statement: no, message: "\(name) takes no parameters")
                }
                try circuit.append(.gate(gate, qubits: qs, parameters: ps))
            } catch let e as CircuitError {
                throw OpenQASMError.parse(statement: no, message: e.localizedDescription)
            }
        }
        return circuit
    }

    private static func parseMeasure(_ stmt: String, into circuit: inout Circuit, statement no: Int) throws {
        let body = stmt.dropFirst("measure".count)
        let parts = body.components(separatedBy: "->")
        guard parts.count == 2 else { throw OpenQASMError.parse(statement: no, message: "measure needs 'q -> c'") }
        let src = parts[0].trimmingCharacters(in: .whitespaces)
        let dst = parts[1].trimmingCharacters(in: .whitespaces)
        switch (firstIndex(in: src), firstIndex(in: dst)) {
        case (nil, nil):
            // Whole-register form: measure q -> c;
            guard circuit.measurementCount == 0 else {
                throw OpenQASMError.parse(statement: no, message: "whole-register measure after single measurements")
            }
            circuit.measureAll()
        case (let q?, let c?):
            guard c == circuit.measurementCount else {
                throw OpenQASMError.parse(
                    statement: no,
                    message: "classical bits must be written in order (expected c[\(circuit.measurementCount)], got c[\(c)]); this package keeps a measurement record, not a classical register")
            }
            try circuit.append(.measure(q))
        default:
            throw OpenQASMError.parse(statement: no, message: "bad measure operands")
        }
    }

    private static func firstIndex(in s: String) -> Int? {
        guard let open = s.firstIndex(of: "["), let close = s.firstIndex(of: "]"), open < close else { return nil }
        return Int(s[s.index(after: open)..<close].trimmingCharacters(in: .whitespaces))
    }

    private static func splitGate(_ stmt: String, statement no: Int) throws -> (String, String?, String) {
        var name = ""
        var i = stmt.startIndex
        while i < stmt.endIndex, stmt[i].isLetter || stmt[i].isNumber || stmt[i] == "_" {
            name.append(stmt[i]); i = stmt.index(after: i)
        }
        guard !name.isEmpty else { throw OpenQASMError.parse(statement: no, message: "cannot parse '\(stmt.prefix(40))'") }
        var rest = stmt[i...].trimmingCharacters(in: .whitespaces)
        var params: String?
        if rest.hasPrefix("(") {
            guard let close = rest.firstIndex(of: ")") else { throw OpenQASMError.parse(statement: no, message: "missing ')'") }
            params = String(rest[rest.index(after: rest.startIndex)..<close])
            rest = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
        }
        return (name.lowercased(), params, rest)
    }

    private static func operands(_ text: String, statement no: Int) throws -> [Int] {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { throw OpenQASMError.parse(statement: no, message: "missing operands") }
        return try parts.map { part in
            guard let n = firstIndex(in: part) else { throw OpenQASMError.parse(statement: no, message: "bad operand '\(part)'") }
            return n
        }
    }

    /// Angle expressions: numbers, pi, + - * /, unary sign, parentheses.
    static func evalAngle(_ expr: String, statement no: Int = 0) throws -> Double {
        let chars = Array(expr.replacingOccurrences(of: " ", with: "").lowercased())
        guard !chars.isEmpty, chars.count <= 64 else { throw OpenQASMError.parse(statement: no, message: "bad angle '\(expr)'") }
        var i = 0
        func peek() -> Character? { i < chars.count ? chars[i] : nil }
        func number() throws -> Double {
            if i + 1 < chars.count, chars[i] == "p", chars[i + 1] == "i" { i += 2; return .pi }
            var s = ""
            while let c = peek(), c.isNumber || c == "." || c == "e" || ((c == "-" || c == "+") && s.last == "e") {
                s.append(c); i += 1
            }
            guard let v = Double(s) else { throw OpenQASMError.parse(statement: no, message: "bad angle '\(expr)'") }
            return v
        }
        func factor() throws -> Double {
            if peek() == "-" { i += 1; return -(try factor()) }
            if peek() == "+" { i += 1; return try factor() }
            if peek() == "(" {
                i += 1
                let v = try sum()
                guard peek() == ")" else { throw OpenQASMError.parse(statement: no, message: "bad angle '\(expr)'") }
                i += 1
                return v
            }
            return try number()
        }
        func term() throws -> Double {
            var v = try factor()
            while let c = peek(), c == "*" || c == "/" {
                i += 1
                let r = try factor()
                v = c == "*" ? v * r : v / r
            }
            return v
        }
        func sum() throws -> Double {
            var v = try term()
            while let c = peek(), c == "+" || c == "-" {
                i += 1
                let r = try term()
                v = c == "+" ? v + r : v - r
            }
            return v
        }
        let v = try sum()
        guard i == chars.count, v.isFinite else { throw OpenQASMError.parse(statement: no, message: "bad angle '\(expr)'") }
        return v
    }
}
