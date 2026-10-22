//
//  StateVectorSimulatorTests.swift
//
//  Exact dense kernel: every gate implemented, nothing skipped, bad input
//  throws. Ported from the SwiftQuantum IDE app's EngineCorrectnessB18Tests.
//

import XCTest
@testable import SwiftQuantumCore

final class StateVectorSimulatorTests: XCTestCase {

    private func probs(_ c: Circuit) throws -> [String: Double] {
        try StateVectorSimulator().probabilities(c)
    }

    func testBellAndBitOrder() throws {
        var bell = Circuit(qubits: 2)
        bell.h(0); bell.cnot(0, 1)
        let p = try probs(bell)
        XCTAssertEqual(p["00"] ?? 0, 0.5, accuracy: 1e-12)
        XCTAssertEqual(p["11"] ?? 0, 0.5, accuracy: 1e-12)
        var x0 = Circuit(qubits: 3)
        x0.x(0)
        XCTAssertEqual(try probs(x0)["001"] ?? 0, 1, accuracy: 1e-12)
    }

    func testToffoliFredkinSwapCZPhaseT() throws {
        var ccx = Circuit(qubits: 3)
        ccx.x(0); ccx.x(1); ccx.ccx(0, 1, 2)
        XCTAssertEqual(try probs(ccx)["111"] ?? 0, 1, accuracy: 1e-12)

        var cswap = Circuit(qubits: 3)
        cswap.x(0); cswap.x(1); cswap.cswap(0, 1, 2)
        XCTAssertEqual(try probs(cswap)["101"] ?? 0, 1, accuracy: 1e-12)

        var swap = Circuit(qubits: 2)
        swap.x(0); swap.swap(0, 1)
        XCTAssertEqual(try probs(swap)["10"] ?? 0, 1, accuracy: 1e-12)

        var ss = Circuit(qubits: 1)
        ss.h(0); ss.s(0); ss.s(0); ss.h(0)
        XCTAssertEqual(try probs(ss)["1"] ?? 0, 1, accuracy: 1e-12)

        var sdg = Circuit(qubits: 1)
        sdg.h(0); sdg.s(0); sdg.sdg(0); sdg.h(0)
        XCTAssertEqual(try probs(sdg)["0"] ?? 0, 1, accuracy: 1e-12)

        var t4 = Circuit(qubits: 1)
        t4.h(0); for _ in 0..<4 { t4.t(0) }; t4.h(0)
        XCTAssertEqual(try probs(t4)["1"] ?? 0, 1, accuracy: 1e-12)

        var cz = Circuit(qubits: 2)
        cz.h(0); cz.x(1); cz.cz(1, 0); cz.h(0)
        XCTAssertEqual(try probs(cz)["11"] ?? 0, 1, accuracy: 1e-12)
    }

    func testRotations() throws {
        var c = Circuit(qubits: 1)
        c.ry(0, theta: 2 * asin(0.6))   // amplitude 0.6 on |1⟩
        XCTAssertEqual(try probs(c)["1"] ?? 0, 0.36, accuracy: 1e-12)
        var rx = Circuit(qubits: 1)
        rx.rx(0, theta: .pi)
        XCTAssertEqual(try probs(rx)["1"] ?? 0, 1, accuracy: 1e-12)
        var rz = Circuit(qubits: 1)
        rz.h(0); rz.rz(0, theta: .pi); rz.h(0)
        XCTAssertEqual(try probs(rz)["1"] ?? 0, 1, accuracy: 1e-12)
    }

    func testStatevectorIsNormalised() throws {
        var c = Circuit(qubits: 5)
        for q in 0..<5 { c.h(q); c.t(q); c.rx(q, theta: 0.3 * Double(q + 1)) }
        for q in 0..<4 { c.cnot(q, q + 1) }
        c.ccx(0, 1, 2)
        let sv = try StateVectorSimulator().statevector(c)
        XCTAssertEqual(sv.count, 32)
        XCTAssertEqual(sv.reduce(0) { $0 + $1.magnitudeSquared }, 1, accuracy: 1e-12)
    }

    func testSamplingMatchesExactDistribution() throws {
        var c = Circuit(qubits: 3)
        c.h(0); c.h(1); c.t(0); c.h(0); c.ccx(0, 1, 2)
        let exact = try probs(c)
        let r = try StateVectorSimulator().run(c, shots: 40_000, seed: 5)
        for (k, v) in exact { XCTAssertEqual(r.probabilities[k] ?? 0, v, accuracy: 0.015, k) }
        for k in r.counts.keys { XCTAssertNotNil(exact[k], "impossible outcome \(k)") }
    }

    func testPartialTerminalMeasurementRecordOrder() throws {
        var c = Circuit(qubits: 3)
        c.x(2)
        c.measure(2); c.measure(0)   // record: [q2 = 1, q0 = 0] → key "01"
        XCTAssertEqual(try StateVectorSimulator().run(c, shots: 10).counts, ["01": 10])
    }

    // MARK: Honest refusals

    func testMidCircuitOperationsAreRefused() {
        var mid = Circuit(qubits: 2)
        mid.h(0); mid.measure(0); mid.t(1)
        XCTAssertThrowsError(try StateVectorSimulator().run(mid, shots: 1))

        var reset = Circuit(qubits: 1)
        reset.t(0); reset.reset(0)
        XCTAssertThrowsError(try StateVectorSimulator().run(reset, shots: 1))

        var noise = Circuit(qubits: 1)
        noise.t(0); noise.xError(0, probability: 0.1)
        XCTAssertThrowsError(try StateVectorSimulator().run(noise, shots: 1))
    }

    func testStatevectorTooLargeThrowsInsteadOfCrashing() {
        var c = Circuit(qubits: 60)
        c.t(0)
        XCTAssertThrowsError(try StateVectorSimulator().run(c, shots: 1)) { error in
            guard case SimulationError.stateVectorTooLarge(let n, _, _) = error else {
                return XCTFail("expected stateVectorTooLarge, got \(error)")
            }
            XCTAssertEqual(n, 60)
        }
    }
}
