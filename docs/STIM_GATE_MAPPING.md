# Stim gate mapping

How this package's operations map to Stim circuit text. Export is
`StimCircuit.export`; import is `StimCircuit.parse`. Import never drops an
instruction silently: anything not listed here throws
`StimParseError.unsupported(line:instruction:)`.

## Both directions

| This package | Stim | Import also accepts |
|---|---|---|
| `i(q)` | `I q` | |
| `x(q)`, `y(q)`, `z(q)` | `X q`, `Y q`, `Z q` | |
| `h(q)` | `H q` | `H_XZ` |
| `s(q)` | `S q` | `SQRT_Z` |
| `sdg(q)` | `S_DAG q` | `SQRT_Z_DAG` |
| `cnot(c, t)` | `CX c t` | `CNOT`, `ZCX` |
| `cz(a, b)` | `CZ a b` | `ZCZ` |
| `swap(a, b)` | `SWAP a b` | |
| `measure(q)` | `M q` | `MZ` |
| `reset(q)` | `R q` | `RZ` |
| `xError(q, p)` | `X_ERROR(p) q` | |
| `yError(q, p)` | `Y_ERROR(p) q` | |
| `zError(q, p)` | `Z_ERROR(p) q` | |
| `depolarize1(q, p)` | `DEPOLARIZE1(p) q` | |
| `detector(-k, …)` | `DETECTOR rec[-k] …` | coordinates, e.g. `DETECTOR(1, 2, 0)`, are ignored |
| `observableInclude(i, -k, …)` | `OBSERVABLE_INCLUDE(i) rec[-k] …` | |
| no explicit measurement | `M 0 1 … n-1` appended on export | |

Export of `t`, `rx`, `ry`, `rz`, `ccx`, `cswap` is refused with
`StimExportError.nonCliffordGate`: Stim has no non-Clifford gates.

## Import only: rewritten exactly with H, S, S†

| Stim | Becomes |
|---|---|
| `MR q`, `MRZ q` | measure, reset |
| `MX q` | H, measure, H |
| `MY q` | S†, H, measure, H, S |
| `RX q` | reset, H |
| `RY q` | reset, H, S |
| `MRX q` | H, measure, reset, H |
| `MRY q` | S†, H, measure, reset, H, S |
| `SQRT_X q` / `SQRT_X_DAG q` | H S H / H S† H |
| `SQRT_Y q` / `SQRT_Y_DAG q` | Z then H / H then Z (equal up to global phase) |
| `CY c t` | S† on t, CX c t, S on t |
| `REPEAT n { … }` | the block, n times (nested blocks too) |
| `TICK`, `QUBIT_COORDS`, `SHIFT_COORDS` | nothing (layout and timing only) |

The qubit count of an imported circuit is the highest qubit index plus one.
These rewrites are covered by `StimImportTests`.

## Refused on import

Measurement flip probabilities (`M(0.01) q`), inverted targets (`M !q`),
`DEPOLARIZE2`, `PAULI_CHANNEL_1/2`, `MPP`, `SPP`, `HERALDED_*`,
`CORRELATED_ERROR` / `E` / `ELSE_CORRELATED_ERROR`, and any other gate not in
the tables above. All 670 annotated memory experiments in QECirc (commit
`8a08057`) import without hitting one of these.
