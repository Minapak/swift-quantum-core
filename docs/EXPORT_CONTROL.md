# Export control record

This is a procedural record of the check made before publishing this
repository. It is not legal advice.

## What the package contains

Quantum circuit simulation code only: a stabilizer tableau simulator, a
dense statevector kernel, a circuit model, and OpenQASM and Stim text
converters. It contains no cryptographic implementation: no encryption,
key exchange, hashing for security, or signatures (`Scripts/check-boundary.sh`
also rejects network code in `Sources`). The randomness it uses is a
pseudo-random generator for sampling, not a cryptographic one.

The SwiftQuantum apps this code was lifted from are classified under ECCN
5D002 because of their cryptographic functions. None of those functions are
in this package.

## Rules checked (15 CFR, eCFR text as of 2026-10-01, read 2026-10-23)

- **§ 734.3(b)(3)(i)**: information and "software" that are published, as
  described in § 734.7, are not subject to the EAR.
- **§ 734.7(a)(4)**: software is "published" when it is made available to the
  public without restrictions on further dissemination, including "posting on
  the Internet on sites available to the public".
- **§ 734.7(b)**: the exception to that rule is published *encryption*
  software classified under ECCN 5D002, which stays subject to the EAR unless
  the § 742.15(b) conditions are met. This package has no encryption
  functionality, so § 734.7(b) and § 742.15(b) do not apply to it.
- **ECCN 4A906 / 4D906 / 4E906** (quantum computers, added in 2024): these
  control quantum computers with stated numbers of working physical qubits and
  C-NOT error rates, and software and technology for their "development" or
  "production". A classical simulator that runs on a phone or laptop is not a
  quantum computer and is not software for developing or producing one. Even
  if it were in scope, published software is outside the EAR under § 734.3(b)(3).

## Conclusion (draft)

The repository is public on GitHub under Apache-2.0, so the package is
"published" software under § 734.7(a)(4) and is not subject to the EAR. No
license, classification request or notification is needed for that. Before it
was made public, the repository was unpublished; this draft found nothing in it
that would have needed a license to share.

## Check record

- Date researched: 2026-10-23
- Researched by: drafted with Claude Code from the eCFR text cited above
- Confirmed by: _Eunmin Park — not yet confirmed_
- Date confirmed: _
- Repository made public on: 2026-10-23 KST (GitHub event, 2026-10-22 23:56 UTC)

The repository was made public before "Confirmed by" was filled in. The owner
still needs to read this record and confirm it.
