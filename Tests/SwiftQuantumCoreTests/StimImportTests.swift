//
//  StimImportTests.swift
//
//  Stim text import: instruction coverage, REPEAT unrolling, refusals, the
//  export → import round trip, and the bundled QECirc circuits.
//

import Testing
import Foundation
@testable import SwiftQuantumCore

@Suite struct StimImportTests {

    @Test func parsesGatesMeasurementsAndAnnotations() throws {
        let c = try StimCircuit.parse("""
            # comment
            QUBIT_COORDS(0, 0) 0
            R 0 1 2
            TICK
            H 0
            CX 0 1 1 2
            X_ERROR(0) 2
            M 0 1
            DETECTOR(1, 0) rec[-1] rec[-2]
            MR 2
            OBSERVABLE_INCLUDE(0) rec[-1] rec[-3]
            """)
        #expect(c.qubitCount == 3)
        #expect(c.measurementCount == 3)
        #expect(c.detectorCount == 1)
        #expect(c.observableCount == 1)
        let events = try #require(try CliffordSimulator().run(c, shots: 50, seed: 1).detectionEvents)
        #expect(events.detectionFraction == 0)
    }

    @Test func repeatBlocksUnroll() throws {
        let c = try StimCircuit.parse("""
            REPEAT 3 {
                H 0
                REPEAT 2 {
                    M 0
                }
            }
            """)
        #expect(c.gateCount == 3)
        #expect(c.measurementCount == 6)
    }

    @Test(arguments: [
        ("SQRT_X 0\nSQRT_X 0\nM 0", "1"),          // √X·√X = X
        ("SQRT_Y 0\nSQRT_Y 0\nM 0", "1"),          // √Y·√Y = Y
        ("SQRT_X 0\nSQRT_X_DAG 0\nM 0", "0"),
        ("SQRT_Y 0\nSQRT_Y_DAG 0\nM 0", "0"),
        ("X 1\nCY 1 0\nM 0", "1"),                 // CY flips the target when control is 1
        ("RX 0\nMX 0", "0"),                       // |+⟩ measured in X is +
        ("RY 0\nMY 0", "0"),                       // |+i⟩ measured in Y is +
        ("RX 0\nZ 0\nMX 0", "1"),
        ("RX 0\nMRX 0\nMX 0", "0"),                // MRX leaves |+⟩, so the second MX reads +
    ])
    func basisChangesAndDecompositionsAreExact(program: String, expectedLast: String) throws {
        let c = try StimCircuit.parse(program)
        let r = try CliffordSimulator().run(c, shots: 40, seed: 3)
        #expect(r.counts.count == 1, "\(program) should be deterministic, got \(r.counts)")
        #expect(r.counts.keys.first?.first.map(String.init) == expectedLast)
    }

    @Test(arguments: ["T 0", "MPP X0*X1", "M !0", "M(0.01) 0", "DEPOLARIZE2(0.1) 0 1", "CX 0", "REPEAT 2 {\nH 0", "}", "DETECTOR 0"])
    func refusesWhatItCannotRepresent(program: String) {
        #expect(throws: (any Error).self) { try StimCircuit.parse("M 0\n" + program) }
    }

    @Test func genuinelyRandomObservableIsRefused() {
        // GHZ qubit 2 alone is random: an observable on it has no reference value.
        #expect(throws: SimulationError.nonDeterministicObservable(0)) {
            try CliffordSimulator().run(try StimCircuit.parse("H 0\nCX 0 1 1 2\nM 0 1 2\nOBSERVABLE_INCLUDE(0) rec[-1]"), shots: 5)
        }
    }

    @Test func exportImportRoundTrip() throws {
        var c = Circuit(qubits: 3)
        c.h(0); c.s(1); c.sdg(2); c.cnot(0, 1); c.cz(1, 2); c.swap(0, 2)
        c.depolarize1(1, probability: 0.25); c.yError(0, probability: 0.5)
        c.measure(0); c.reset(0); c.measure(1); c.detector(-1, -2); c.measure(2)
        c.observableInclude(0, -1); c.observableInclude(1, -2, -3)
        let back = try StimCircuit.parse(try StimCircuit.export(c))
        #expect(back == c)
    }

    // MARK: Bundled QECirc circuits (CC BY-SA 4.0)

    static let qecircFiles = [
        "rotated-surface-code-d-3--alphasyndrome-schedule-mwpm",
        "rotated-surface-code-d-3--depth-optimal-schedule",
        "rotated-surface-code-d-5--alphasyndrome-schedule-mwpm",
    ]

    static func qecirc(_ name: String) throws -> Circuit {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "stim", subdirectory: "qecirc"))
        return try StimCircuit.parse(String(contentsOf: url, encoding: .utf8))
    }

    @Test(arguments: qecircFiles)
    func qecircMemoryCircuitIsQuietWithoutNoise(name: String) throws {
        let c = try Self.qecirc(name)
        #expect(c.isCliffordOnly)
        #expect(c.detectorCount > 0 && c.observableCount == 1)
        let events = try #require(try CliffordSimulator().run(c, shots: 20, seed: 1).detectionEvents)
        #expect(events.detectionFraction == 0)
        #expect(events.observableFlips.allSatisfy { $0 == [false] })
    }

    @Test func qecircD3ShapeMatchesQECircMetadata() throws {
        let c = try Self.qecirc("rotated-surface-code-d-3--alphasyndrome-schedule-mwpm")
        #expect(c.qubitCount == 17)
        // 3 rounds × 8 ancillas + 9 data measurements
        #expect(c.measurementCount == 33)
        // 4 Z detectors in round 1, 8 in each of 2 repeated rounds, 4 final
        #expect(c.detectorCount == 24)
    }

    @Test func qecircWithNoiseFiresDetectorsAndExportsForDecoders() throws {
        let c = try Self.qecirc("rotated-surface-code-d-3--alphasyndrome-schedule-mwpm").addingUniformNoise(probability: 0.01)
        let events = try #require(try CliffordSimulator().run(c, shots: 2000, seed: 5).detectionEvents)
        #expect(events.detectionFraction > 0.01)
        let lines = events.formatted01().split(separator: "\n")
        #expect(lines.count == 2000)
        #expect(lines.allSatisfy { $0.count == events.detectorCount + events.observableCount })
        #expect(try StimCircuit.export(c).contains("DEPOLARIZE1(0.01)"))
    }

    @Test func bundledCopiesMatchThirdPartyFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let thirdParty = root.appendingPathComponent("third_party/qecirc")
        // Source paths only exist when testing on the build machine.
        guard FileManager.default.fileExists(atPath: thirdParty.path) else { return }
        for name in Self.qecircFiles {
            let a = try Data(contentsOf: thirdParty.appendingPathComponent(name + ".stim"))
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "stim", subdirectory: "qecirc"))
            #expect(a == (try Data(contentsOf: url)), "\(name) drifted from third_party/qecirc")
        }
    }
}
