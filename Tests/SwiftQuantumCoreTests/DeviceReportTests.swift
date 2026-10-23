//
//  DeviceReportTests.swift
//
//  Prints the capability table for whatever device runs the tests (a Mac
//  with `swift test`, an iPhone with `xcodebuild test`), and checks the
//  results are right. Timing depends on the build configuration; the
//  README numbers come from Release builds.
//

import XCTest
import SwiftQuantumCore

final class DeviceReportTests: XCTestCase {

    private func hardwareModel() -> String {
        #if canImport(Darwin)
        for key in ["hw.machine", "hw.model"] {
            var size = 0
            sysctlbyname(key, nil, &size, nil, 0)
            var bytes = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname(key, &bytes, &size, nil, 0)
            let value = String(cString: bytes)
            if value.contains(",") { return value }
        }
        #endif
        return "unknown"
    }

    func testCapabilityReport() throws {
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        let info = ProcessInfo.processInfo
        print("DEVICE-REPORT machine \(hardwareModel()) · \(info.operatingSystemVersionString) · \(info.physicalMemory / 1_048_576) MB · \(build) build")

        for n in [25, 64, 127] {
            var c = Circuit(qubits: n)
            c.h(0)
            for q in 1..<n { c.cnot(0, q) }
            let r = try CliffordSimulator().run(c, shots: 100, seed: 1)
            let zeros = String(repeating: "0", count: n), ones = String(repeating: "1", count: n)
            XCTAssertTrue(Set(r.counts.keys).isSubset(of: [zeros, ones]))
            print(String(format: "DEVICE-REPORT stabilizer GHZ %3d qubits, 100 shots: %9.1f ms, %d bytes", n, r.elapsedMilliseconds, r.stateMemoryBytes))
        }

        // 25 dense qubits takes minutes in a debug build; measure it only in Release.
        #if DEBUG
        let denseSizes = [16, 20]
        #else
        let denseSizes = [20, 25]
        #endif
        for n in denseSizes {
            var c = Circuit(qubits: n)
            for q in 0..<n { c.h(q); c.t(q) }
            for q in 0..<(n - 1) { c.cnot(q, q + 1) }
            let r = try StateVectorSimulator().run(c, shots: 100, seed: 1)
            XCTAssertEqual(r.counts.values.reduce(0, +), 100)
            print(String(format: "DEVICE-REPORT statevector H·T·CNOT %2d qubits, 100 shots: %9.1f ms, %d bytes", n, r.elapsedMilliseconds, r.stateMemoryBytes))
        }

        let url = try XCTUnwrap(Bundle.module.url(forResource: "rotated-surface-code-d-3--alphasyndrome-schedule-mwpm",
                                                  withExtension: "stim", subdirectory: "qecirc"))
        let qecirc = try StimCircuit.parse(String(contentsOf: url, encoding: .utf8)).addingUniformNoise(probability: 0.005)
        let r = try CliffordSimulator().run(qecirc, shots: 10_000, seed: 2026)
        let events = try XCTUnwrap(r.detectionEvents)
        XCTAssertEqual(events.detectionFraction, 0.0695, accuracy: 0.004)
        print(String(format: "DEVICE-REPORT QECirc #1289 d=3 + noise 0.005, 10000 shots: %9.1f ms, detection fraction %.4f",
                     r.elapsedMilliseconds, events.detectionFraction))
    }
}
