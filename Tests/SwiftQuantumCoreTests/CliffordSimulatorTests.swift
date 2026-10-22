//
//  CliffordSimulatorTests.swift
//
//  Locks the stabilizer engine: the allowlist never admits a non-Clifford
//  gate (that would be a wrong answer, not an error), the CHP math is right,
//  and bit order matches the dense kernel (qubit 0 = rightmost character).
//  Ported from the SwiftQuantum IDE app's CliffordSimulatorTests.
//

import XCTest
@testable import SwiftQuantumCore

final class CliffordSimulatorTests: XCTestCase {

    // MARK: Allowlist

    func testCliffordAllowlist() {
        let clifford: [Gate] = [.identity, .pauliX, .pauliY, .pauliZ, .hadamard, .s, .sDagger, .cnot, .cz, .swap]
        for g in clifford { XCTAssertTrue(g.isClifford, "\(g.rawValue) should be Clifford") }
        let nonClifford: [Gate] = [.t, .rx, .ry, .rz, .toffoli, .fredkin]
        for g in nonClifford { XCTAssertFalse(g.isClifford, "\(g.rawValue) must not be treated as Clifford") }
        XCTAssertEqual(Set(clifford + nonClifford), Set(Gate.allCases))
    }

    func testNonCliffordCircuitThrows() {
        var c = Circuit(qubits: 2)
        c.h(0); c.t(0); c.cnot(0, 1)
        XCTAssertFalse(c.isCliffordOnly)
        XCTAssertThrowsError(try CliffordSimulator().run(c, shots: 16)) { error in
            XCTAssertEqual(error as? SimulationError, .nonCliffordGate(.t, operationIndex: 1))
        }
    }

    // MARK: Correctness

    func testBellPairOnlyCorrelatedStates() throws {
        var c = Circuit(qubits: 2)
        c.h(0); c.cnot(0, 1)
        let r = try CliffordSimulator().run(c, shots: 500, seed: 1)
        XCTAssertEqual(Set(r.counts.keys), ["00", "11"])
        XCTAssertEqual(r.counts.values.reduce(0, +), 500)
        XCTAssertEqual(r.engine, .stabilizer)
    }

    /// The README Quick Start, verbatim.
    func testQuickStart127QubitGHZ() throws {
        var c = Circuit(qubits: 127)
        c.h(0)
        for q in 1..<127 { c.cnot(0, q) }   // 127-qubit GHZ, all Clifford
        let sim = CliffordSimulator()
        let result = try sim.run(c, shots: 100)

        let allZero = String(repeating: "0", count: 127)
        let allOne = String(repeating: "1", count: 127)
        XCTAssertTrue(Set(result.counts.keys).isSubset(of: [allZero, allOne]))
        XCTAssertEqual(result.counts.values.reduce(0, +), 100)
        XCTAssertEqual(result.stateMemoryBytes, 255 * 255)
        XCTAssertEqual(result.probabilities.values.reduce(0, +), 1, accuracy: 1e-12)
    }

    func testSingleQubitIdentities() throws {
        // H S S H = H Z H = X ; H S S† H = I ; S S S S = I
        func outcome(_ build: (inout Circuit) -> Void) throws -> String {
            var c = Circuit(qubits: 1)
            build(&c)
            let r = try CliffordSimulator().run(c, shots: 50, seed: 3)
            XCTAssertEqual(r.counts.count, 1, "deterministic circuit gave \(r.counts)")
            return r.counts.keys.first!
        }
        XCTAssertEqual(try outcome { $0.h(0); $0.s(0); $0.s(0); $0.h(0) }, "1")
        XCTAssertEqual(try outcome { $0.h(0); $0.s(0); $0.sdg(0); $0.h(0) }, "0")
        XCTAssertEqual(try outcome { $0.h(0); $0.sdg(0); $0.sdg(0); $0.h(0) }, "1")
        XCTAssertEqual(try outcome { $0.x(0); $0.y(0) }, "0")
        XCTAssertEqual(try outcome { $0.h(0); $0.z(0); $0.h(0) }, "1")
    }

    func testTwoQubitGates() throws {
        var swap = Circuit(qubits: 2)
        swap.x(0); swap.swap(0, 1)
        XCTAssertEqual(try CliffordSimulator().run(swap, shots: 10).counts, ["10": 10])

        // CZ between |+⟩ and |1⟩ flips the phase, so H brings qubit 0 to |1⟩.
        var cz = Circuit(qubits: 2)
        cz.h(0); cz.x(1); cz.cz(1, 0); cz.h(0)
        XCTAssertEqual(try CliffordSimulator().run(cz, shots: 10).counts, ["11": 10])
    }

    // MARK: Bit order (qubit 0 = rightmost), matching the dense kernel

    func testBitOrder() throws {
        var low = Circuit(qubits: 3)
        low.h(0)
        XCTAssertTrue(Set(try CliffordSimulator().run(low, shots: 400, seed: 5).counts.keys).isSubset(of: ["000", "001"]))
        var high = Circuit(qubits: 3)
        high.x(2)
        XCTAssertEqual(Set(try CliffordSimulator().run(high, shots: 64).counts.keys), ["100"])
    }

    // MARK: Seeds (pseudo-random, reproducible)

    func testSeedReproducibility() throws {
        var c = Circuit(qubits: 8)
        for q in 0..<8 { c.h(q) }
        let a = try CliffordSimulator().run(c, shots: 300, seed: 42)
        let b = try CliffordSimulator().run(c, shots: 300, seed: 42)
        let d = try CliffordSimulator().run(c, shots: 300, seed: 43)
        XCTAssertEqual(a.counts, b.counts)
        XCTAssertNotEqual(a.counts, d.counts)
    }

    func testInvalidShots() {
        XCTAssertThrowsError(try CliffordSimulator().run(Circuit(qubits: 1), shots: 0))
    }

    // MARK: Measurement record, reset, noise

    func testMidCircuitMeasurementAndReset() throws {
        var c = Circuit(qubits: 1)
        c.x(0); c.measure(0)      // record 0 = 1
        c.reset(0); c.measure(0)  // record 1 = 0
        c.h(0); c.h(0); c.x(0); c.measure(0) // record 2 = 1
        // record entry 0 is the rightmost character
        XCTAssertEqual(try CliffordSimulator().run(c, shots: 20).counts, ["101": 20])
    }

    func testResetOfRandomQubitIsZero() throws {
        var c = Circuit(qubits: 2)
        c.h(0); c.cnot(0, 1); c.reset(0); c.measure(0)
        XCTAssertEqual(try CliffordSimulator().run(c, shots: 200, seed: 9).counts, ["0": 200])
    }

    func testNoiseWithProbabilityOneAndZero() throws {
        var always = Circuit(qubits: 1)
        always.xError(0, probability: 1); always.measure(0)
        XCTAssertEqual(try CliffordSimulator().run(always, shots: 50).counts, ["1": 50])

        var never = Circuit(qubits: 1)
        never.xError(0, probability: 0); never.depolarize1(0, probability: 0); never.measure(0)
        XCTAssertEqual(try CliffordSimulator().run(never, shots: 50).counts, ["0": 50])

        var phase = Circuit(qubits: 1)
        phase.h(0); phase.zError(0, probability: 1); phase.h(0); phase.measure(0)
        XCTAssertEqual(try CliffordSimulator().run(phase, shots: 50).counts, ["1": 50])
    }

    func testDepolarizeRate() throws {
        // DEPOLARIZE1(p) flips a Z measurement when it applies X or Y: rate 2p/3.
        var c = Circuit(qubits: 1)
        c.depolarize1(0, probability: 0.3); c.measure(0)
        let r = try CliffordSimulator().run(c, shots: 20_000, seed: 11)
        XCTAssertEqual(r.probabilities["1"] ?? 0, 0.2, accuracy: 0.015)
    }

    // MARK: Detectors

    private func repetitionMemory(p: Double, rounds: Int) -> Circuit {
        var c = Circuit(qubits: 5)
        for round in 0..<rounds {
            for d in [0, 2, 4] { c.xError(d, probability: p) }
            c.cnot(0, 1); c.cnot(2, 1); c.cnot(2, 3); c.cnot(4, 3)
            c.measure(1); c.measure(3); c.reset(1); c.reset(3)
            if round == 0 { c.detector(-2); c.detector(-1) } else { c.detector(-2, -4); c.detector(-1, -3) }
        }
        c.measure(0); c.measure(2); c.measure(4)
        c.detector(-3, -2, -5); c.detector(-2, -1, -4)
        c.observableInclude(0, -1)
        return c
    }

    func testNoiselessDetectorsNeverFire() throws {
        let c = repetitionMemory(p: 0, rounds: 3)
        XCTAssertEqual(c.detectorCount, 8)
        XCTAssertEqual(c.observableCount, 1)
        let events = try XCTUnwrap(try CliffordSimulator().run(c, shots: 200, seed: 1).detectionEvents)
        XCTAssertEqual(events.detectionFraction, 0)
        XCTAssertTrue(events.observableFlips.allSatisfy { $0 == [false] })
        XCTAssertEqual(events.formatted01().split(separator: "\n").first, "000000000")
    }

    func testObservableFlipRateMatchesTheory() throws {
        // Data qubit 4 flips an odd number of times over 3 rounds: (1 - (1-2p)^3) / 2.
        let p = 0.05
        let events = try XCTUnwrap(try CliffordSimulator().run(repetitionMemory(p: p, rounds: 3),
                                                              shots: 20_000, seed: 7).detectionEvents)
        let rate = Double(events.observableFlips.filter { $0[0] }.count) / 20_000
        XCTAssertEqual(rate, (1 - pow(1 - 2 * p, 3)) / 2, accuracy: 0.012)
        XCTAssertGreaterThan(events.detectionFraction, 0)
    }

    func testSingleErrorFiresTheExpectedDetectors() throws {
        // A certain X error on data qubit 0 before round 0 trips detector 0 only
        // (and the final-round check involving qubit 0 sees no change).
        var c = Circuit(qubits: 5)
        c.xError(0, probability: 1)
        c.cnot(0, 1); c.cnot(2, 1); c.cnot(2, 3); c.cnot(4, 3)
        c.measure(1); c.measure(3)
        c.detector(-2); c.detector(-1)
        let events = try XCTUnwrap(try CliffordSimulator().run(c, shots: 5).detectionEvents)
        XCTAssertTrue(events.detectorFlips.allSatisfy { $0 == [true, false] })
    }

    func testNonDeterministicDetectorIsRefused() {
        var c = Circuit(qubits: 1)
        c.h(0); c.measure(0); c.detector(-1)
        XCTAssertThrowsError(try CliffordSimulator().run(c, shots: 10)) { error in
            XCTAssertEqual(error as? SimulationError, .nonDeterministicDetector(0))
        }
    }

    // MARK: Router

    func testRouterPicksEngine() throws {
        var clifford = Circuit(qubits: 40)
        clifford.h(0)
        XCTAssertEqual(try Simulator().run(clifford, shots: 4).engine, .stabilizer)
        var dense = Circuit(qubits: 2)
        dense.h(0); dense.t(0)
        XCTAssertEqual(try Simulator().run(dense, shots: 4).engine, .statevector)
    }
}
