// Reproduces the README capability table on the machine that runs it.
//   swift run -c release capability-report

import Foundation
import SwiftQuantumCore

func ghz(_ n: Int) -> Circuit {
    var c = Circuit(qubits: n)
    c.h(0)
    for q in 1..<n { c.cnot(0, q) }
    return c
}

/// A non-Clifford layer circuit (H and T on every qubit, then a CNOT chain).
func layered(_ n: Int) -> Circuit {
    var c = Circuit(qubits: n)
    for q in 0..<n { c.h(q); c.t(q) }
    for q in 0..<(n - 1) { c.cnot(q, q + 1) }
    return c
}

let info = ProcessInfo.processInfo

/// Hardware identifier, e.g. "Mac17,7" or "iPhone17,1".
func hardwareModel() -> String {
    #if canImport(Darwin)
    for key in ["hw.machine", "hw.model"] {
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname(key, &bytes, &size, nil, 0)
        let value = String(cString: bytes)
        if value.contains(",") { return value }   // skip bare "arm64"
    }
    #endif
    var sys = utsname()
    uname(&sys)
    return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
}
let machine = hardwareModel()
print("machine \(machine) · \(info.operatingSystemVersionString) · \(info.physicalMemory / 1_048_576) MB RAM · \(info.activeProcessorCount) cores")
#if DEBUG
print("WARNING: debug build. Use `swift run -c release capability-report` for representative numbers.")
#endif
print("")
print("engine        circuit          qubits  shots   time_ms   state_bytes")

for n in [25, 64, 127] {
    let r = try CliffordSimulator().run(ghz(n), shots: 100, seed: 1)
    let ok = r.counts.keys.allSatisfy { $0.allSatisfy { $0 == "0" } || $0.allSatisfy { $0 == "1" } }
    print(String(format: "stabilizer    GHZ%@  %6d  %5d  %8.1f  %12d", ok ? "        " : " (BAD)  ", n, r.shots, r.elapsedMilliseconds, r.stateMemoryBytes))
}
for n in [10, 16, 20, 22] {
    let r = try StateVectorSimulator().run(layered(n), shots: 100, seed: 1)
    print(String(format: "statevector   H·T·CNOT layer  %6d  %5d  %8.1f  %12d", n, r.shots, r.elapsedMilliseconds, r.stateMemoryBytes))
}
print("")
print("Clifford circuits only for the stabilizer rows · dense range is documented, not enforced · simulator, not hardware")
