# QECirc circuits

These circuit files come from QECirc, a community-driven library of quantum
error correction circuits (https://qecirc.com, source repository
https://github.com/qecirc/qecirc-website), created and maintained by Ludwig
Schmid and Tom Peham and funded by the Unitary Foundation.

**License: these files are not Apache-2.0.** They are licensed under the
Creative Commons Attribution-ShareAlike 4.0 International License
(CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/legalcode); see
`LICENSE-DATA`, copied unchanged from QECirc. The rest of this repository is
Apache-2.0.

Taken from commit `8a08057f933785a3bc9dd320df084e24ff378bf0` (2026-10-17) of
qecirc-website, `data_yaml/circuits/`:

| File here | QECirc id | Circuit | Original source |
|---|---|---|---|
| `rotated-surface-code-d-3--alphasyndrome-schedule-mwpm.stim` | #1289 | Rotated surface code d=3, AlphaSyndrome schedule (MWPM) | arXiv:2601.12509 |
| `rotated-surface-code-d-3--depth-optimal-schedule.stim` | #1290 | Rotated surface code d=3, depth-optimal schedule | arXiv:2601.12509 |
| `rotated-surface-code-d-5--alphasyndrome-schedule-mwpm.stim` | #1291 | Rotated surface code d=5, AlphaSyndrome schedule (MWPM) | arXiv:2601.12509 |

Changes: each `.stim` file is QECirc's `.stim-annotated` file (the syndrome
round wrapped as a noiseless memory experiment with detectors and a logical
observable), renamed from `.stim-annotated` to `.stim`. The contents are
unchanged. The matching `.yaml` metadata files are copied unchanged.
Noise is added at run time by `Circuit.addingUniformNoise(probability:)`, not
written into these files.

QECirc is where QEC circuits are found and shared; this package is where they
run in a pocket. Copies for the test bundle are in
`Tests/SwiftQuantumCoreTests/Resources/qecirc/` under the same license.
