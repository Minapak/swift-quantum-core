//
//  QECircCorpusTests.swift
//
//  Optional corpus check against a local clone of the QECirc library
//  (github.com/qecirc/qecirc-website). Skipped unless QECIRC_DIR points at
//  the clone:
//
//      QECIRC_DIR=/path/to/qecirc-website swift test --filter QECircCorpusTests
//
//  Every `.stim-annotated` memory experiment must import, and every one up to
//  QECIRC_MAX_QUBITS qubits (default 100) must run noiselessly on the
//  stabilizer simulator and fire no detector. Larger ones are counted as
//  skipped (the byte-per-cell tableau is slow there; Stim is the tool for them).
//

import XCTest
@testable import SwiftQuantumCore

final class QECircCorpusTests: XCTestCase {
    func testEveryAnnotatedCircuitImportsAndIsQuietWithoutNoise() throws {
        guard let dir = ProcessInfo.processInfo.environment["QECIRC_DIR"] else {
            throw XCTSkip("set QECIRC_DIR to a clone of qecirc-website to run the corpus check")
        }
        let circuits = URL(fileURLWithPath: dir).appendingPathComponent("data_yaml/circuits")
        let files = try FileManager.default.contentsOfDirectory(at: circuits, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "stim-annotated" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty)
        var failures: [String] = []
        var unsupported: [String: Int] = [:]
        var checked = 0
        var skippedLarge = 0
        let maxQubits = Int(ProcessInfo.processInfo.environment["QECIRC_MAX_QUBITS"] ?? "") ?? 100
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let circuit: Circuit
            do {
                circuit = try StimCircuit.parse(text)
            } catch let StimParseError.unsupported(_, name) {
                unsupported[name, default: 0] += 1
                continue
            } catch {
                failures.append("\(file.lastPathComponent): parse \(error)")
                continue
            }
            if circuit.qubitCount > maxQubits { skippedLarge += 1; continue }
            do {
                let r = try CliffordSimulator().run(circuit, shots: 8, seed: 1)
                if let e = r.detectionEvents, e.detectionFraction != 0 || e.observableFlips.contains(where: { $0.contains(true) }) {
                    failures.append("\(file.lastPathComponent): detectors fired without noise")
                }
                checked += 1
            } catch {
                failures.append("\(file.lastPathComponent): run \(error)")
            }
        }
        print("QECirc corpus: \(files.count) annotated circuits, \(checked) ran quiet, \(skippedLarge) imported but skipped (> \(maxQubits) qubits), unsupported \(unsupported), failures \(failures.count)")
        for f in failures.prefix(20) { print("  " + f) }
        XCTAssertTrue(failures.isEmpty)
    }
}
