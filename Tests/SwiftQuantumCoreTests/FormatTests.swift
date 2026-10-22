//
//  FormatTests.swift
//
//  OpenQASM 2.0 import/export and Stim circuit text export.
//

import XCTest
@testable import SwiftQuantumCore

final class FormatTests: XCTestCase {

    // MARK: OpenQASM

    func testQASMRoundTrip() throws {
        var c = Circuit(qubits: 4)
        c.h(0); c.cnot(0, 3); c.rz(2, theta: -.pi / 2); c.ccx(0, 1, 2); c.cswap(2, 1, 3)
        c.swap(0, 1); c.cz(1, 3); c.s(0); c.sdg(2); c.t(1)
        let text = OpenQASM.export(c)
        XCTAssertTrue(text.hasSuffix("measure q -> c;\n"))
        let back = try OpenQASM.parse(text)
        XCTAssertEqual(back.qubitCount, 4)
        XCTAssertEqual(back.gateCount, c.gateCount)
        XCTAssertEqual(back.measurementCount, 4, "whole-register measure becomes measureAll")
        let a = try StateVectorSimulator().probabilities(c)
        let b = try StateVectorSimulator().probabilities(back)
        for (k, v) in a { XCTAssertEqual(b[k] ?? 0, v, accuracy: 1e-12) }
        XCTAssertEqual(OpenQASM.export(try OpenQASM.parse(OpenQASM.export(back))), OpenQASM.export(back))
    }

    func testQASMMeasureAndReset() throws {
        let c = try OpenQASM.parse("""
            OPENQASM 2.0;
            include "qelib1.inc";
            qreg q[2];
            creg c[2];
            x q[1];
            measure q[1] -> c[0];
            reset q[1];
            measure q[1] -> c[1];
            """)
        XCTAssertEqual(c.measurementCount, 2)
        XCTAssertEqual(try CliffordSimulator().run(c, shots: 5).counts, ["01": 5])
        XCTAssertThrowsError(try OpenQASM.parse("qreg q[2]; measure q[0] -> c[1];"),
                             "out-of-order classical bits must be refused, not silently reordered")
    }

    func testQASMImportVariantsAndErrors() throws {
        let c = try OpenQASM.parse("OPENQASM 2.0; include \"qelib1.inc\"; qreg q[2]; // x\n rx( -pi/2 ) q[1] ; cx q[0], q[1];")
        XCTAssertEqual(c.gateCount, 2)
        guard case .gate(.rx, _, let ps) = c.operations[0] else { return XCTFail() }
        XCTAssertEqual(ps[0], -.pi / 2, accuracy: 1e-12)
        XCTAssertThrowsError(try OpenQASM.parse("qreg q[2]; u3(0.1,0.2,0.3) q[0];"))
        XCTAssertThrowsError(try OpenQASM.parse(""))
        XCTAssertThrowsError(try OpenQASM.parse("qreg q[2]; cx q[0], q[0];"), "repeated qubit")
        XCTAssertThrowsError(try OpenQASM.parse("qreg q[2]; h q[5];"), "qubit out of range")
        XCTAssertThrowsError(try OpenQASM.parse("qreg q[2]; qreg r[2]; h q[0];"), "second register")
        XCTAssertThrowsError(try OpenQASM.evalAngle("alert(1)"))
        XCTAssertEqual(try OpenQASM.evalAngle("2*pi/4"), .pi / 2, accuracy: 1e-12)
    }

    func testQASMWritesAnnotationsAsComments() {
        var c = Circuit(qubits: 1)
        c.xError(0, probability: 0.01); c.measure(0); c.detector(-1)
        let text = OpenQASM.export(c)
        XCTAssertTrue(text.contains("// X_ERROR(0.01) q[0]; not representable in OpenQASM 2.0"))
        XCTAssertTrue(text.contains("// DETECTOR c[0]; not representable in OpenQASM 2.0"))
    }

    // MARK: Stim

    func testStimExport() throws {
        var c = Circuit(qubits: 3)
        c.h(0); c.s(1); c.sdg(1); c.cnot(0, 1); c.cz(1, 2); c.swap(0, 2)
        c.depolarize1(2, probability: 0.001)
        c.measure(0); c.measure(1); c.reset(0)
        c.detector(-1, -2)
        c.measure(2)
        c.observableInclude(0, -1, -3)
        XCTAssertEqual(try StimCircuit.export(c), """
            H 0
            S 1
            S_DAG 1
            CX 0 1
            CZ 1 2
            SWAP 0 2
            DEPOLARIZE1(0.001) 2
            M 0
            M 1
            R 0
            DETECTOR rec[-1] rec[-2]
            M 2
            OBSERVABLE_INCLUDE(0) rec[-1] rec[-3]

            """)
    }

    func testStimExportAddsImplicitMeasurementAndRefusesNonClifford() throws {
        var bell = Circuit(qubits: 2)
        bell.h(0); bell.cnot(0, 1)
        XCTAssertEqual(try StimCircuit.export(bell), "H 0\nCX 0 1\nM 0 1\n")

        var t = Circuit(qubits: 1)
        t.t(0)
        XCTAssertThrowsError(try StimCircuit.export(t)) { error in
            XCTAssertEqual(error as? StimExportError, .nonCliffordGate(.t, operationIndex: 0))
        }
    }

    // MARK: Circuit model

    func testValidatedAppend() {
        var c = Circuit(qubits: 2)
        XCTAssertThrowsError(try c.append(.gate(.cnot, qubits: [0], parameters: [])))
        XCTAssertThrowsError(try c.append(.gate(.rx, qubits: [0], parameters: [])))
        XCTAssertThrowsError(try c.append(.noise(.xError, qubit: 0, probability: 1.5)))
        XCTAssertThrowsError(try c.append(.detector(records: [0])), "no measurement yet")
        XCTAssertNoThrow(try c.append(.measure(0)))
        XCTAssertNoThrow(try c.append(.detector(records: [0])))
    }

    func testDepth() {
        var c = Circuit(qubits: 3)
        c.h(0); c.h(1); c.cnot(0, 2); c.x(1)
        XCTAssertEqual(c.depth, 2)
        var chain = Circuit(qubits: 3)
        chain.h(0); chain.cnot(0, 1); chain.cnot(1, 2)
        XCTAssertEqual(chain.depth, 3)
        XCTAssertEqual(Circuit(qubits: 2).depth, 0)
    }

    func testCodableRoundTrip() throws {
        var c = Circuit(qubits: 2)
        c.h(0); c.rz(1, theta: 0.25); c.measure(0); c.detector(-1)
        let back = try JSONDecoder().decode(Circuit.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        XCTAssertEqual(back.measurementCount, 1)

        // A qubit index outside the register must fail to decode, not crash later.
        var json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"qubitCount\":2", with: "\"qubitCount\":1")
        XCTAssertThrowsError(try JSONDecoder().decode(Circuit.self, from: Data(json.utf8)))
    }
}

/// The README snippets, verbatim, so the documentation cannot drift from the API.
final class ReadmeSnippetTests: XCTestCase {
    func testDetectionEventsSnippet() throws {
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

        XCTAssertEqual(events.split(separator: "\n").count, 10_000)
        XCTAssertEqual(result.detectionEvents!.detectionFraction, 0.01, accuracy: 0.004)
        XCTAssertTrue(stimText.contains("DETECTOR rec[-1]"))
    }

    func testReadmeQuickStartMatchesExample() throws {
        let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let example = try String(contentsOf: packageRoot.appendingPathComponent("Examples/GHZ127/main.swift"), encoding: .utf8)
        let quickStart = """
            var c = Circuit(qubits: 127)
            c.h(0)
            for q in 1..<127 { c.cnot(0, q) }   // 127-qubit GHZ, all Clifford
            let sim = CliffordSimulator()
            let result = try sim.run(c, shots: 100)
            """
        XCTAssertTrue(readme.contains(quickStart), "README Quick Start drifted")
        XCTAssertTrue(example.contains(quickStart), "Examples/GHZ127 drifted from the README Quick Start")
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
