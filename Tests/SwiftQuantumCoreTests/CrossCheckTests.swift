//
//  CrossCheckTests.swift
//
//  The two simulators are independent implementations. On random Clifford
//  circuits small enough for the dense kernel, the stabilizer sampler must
//  only produce outcomes the exact distribution allows, at the right rates.
//

import XCTest
@testable import SwiftQuantumCore

final class CrossCheckTests: XCTestCase {

    private func randomClifford(qubits n: Int, gates: Int, rng: inout Xoshiro256StarStar) -> Circuit {
        var c = Circuit(qubits: n)
        for _ in 0..<gates {
            let a = Int.random(in: 0..<n, using: &rng)
            var b = Int.random(in: 0..<n, using: &rng)
            if b == a { b = (a + 1) % n }
            switch Int.random(in: 0..<9, using: &rng) {
            case 0: c.h(a)
            case 1: c.s(a)
            case 2: c.sdg(a)
            case 3: c.x(a)
            case 4: c.y(a)
            case 5: c.z(a)
            case 6: c.cnot(a, b)
            case 7: c.cz(a, b)
            default: c.swap(a, b)
            }
        }
        return c
    }

    func testStabilizerAgreesWithDenseKernel() throws {
        var rng = Xoshiro256StarStar(seed: 2026)
        for trial in 0..<40 {
            let n = 2 + trial % 5
            let c = randomClifford(qubits: n, gates: 6 * n, rng: &rng)
            let exact = try StateVectorSimulator().probabilities(c)
            let sampled = try CliffordSimulator().run(c, shots: 4000, seed: UInt64(trial))
            for (k, v) in sampled.probabilities {
                let e = try XCTUnwrap(exact[k], "trial \(trial): stabilizer produced impossible \(k)")
                XCTAssertEqual(v, e, accuracy: 0.05, "trial \(trial) \(k)")
            }
            // Clifford output distributions are uniform over their support.
            for (k, v) in exact { XCTAssertNotNil(sampled.counts[k], "trial \(trial): missing \(k) (p = \(v))") }
        }
    }
}
