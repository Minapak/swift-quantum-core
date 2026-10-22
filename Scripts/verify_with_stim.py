"""Re-run `repetition-memory`'s exported circuit in Stim and decode with PyMatching.

Run from the directory where `swift run repetition-memory` wrote its files:

    python3 -m venv .venv && . .venv/bin/activate && pip install stim pymatching
    swift run repetition-memory 0.05 10000
    python3 Scripts/verify_with_stim.py repetition_memory.stim repetition_memory.01

It compares the detection fraction and raw observable flip rate measured on
the device with Stim's, then decodes both sets of detection events with
PyMatching. Decoding happens here, in Stim and PyMatching, not in the package.
"""

import sys

import numpy as np
import pymatching
import stim


def main(stim_path: str, events_path: str) -> None:
    circuit = stim.Circuit(open(stim_path).read())
    n_det = circuit.num_detectors
    n_obs = circuit.num_observables

    rows = [line.strip() for line in open(events_path) if line.strip()]
    device = np.array([[c == "1" for c in row] for row in rows], dtype=bool)
    if device.shape[1] != n_det + n_obs:
        raise SystemExit(f"{events_path}: {device.shape[1]} columns, expected {n_det} detectors + {n_obs} observables")
    device_det, device_obs = device[:, :n_det], device[:, n_det:]

    shots = device.shape[0]
    stim_det, stim_obs = circuit.compile_detector_sampler().sample(shots, separate_observables=True)

    print(f"shots {shots}, detectors {n_det}, observables {n_obs}")
    print(f"detection fraction   device {device_det.mean():.4f}   stim {stim_det.mean():.4f}")
    print(f"raw observable flips device {device_obs.mean():.4f}   stim {stim_obs.mean():.4f}")

    # Per-column agreement: z-score of the difference of two binomial rates.
    dev = device.mean(axis=0)
    ref = np.concatenate([stim_det, stim_obs], axis=1).mean(axis=0)
    pooled = (dev + ref) / 2
    se = np.sqrt(np.maximum(pooled * (1 - pooled), 1e-12) * 2 / shots)
    z = np.abs(dev - ref) / se
    worst = int(np.argmax(z))
    print(f"per-column rates: max |z| = {z.max():.2f} (column {worst}), columns with |z| > 4: {int((z > 4).sum())} of {len(z)}")
    # Pairwise correlations between detectors carry the error structure the decoder uses.
    dc = np.corrcoef(device_det.T.astype(float)) if n_det > 1 else np.zeros((1, 1))
    sc = np.corrcoef(stim_det.T.astype(float)) if n_det > 1 else np.zeros((1, 1))
    print(f"detector correlation matrices: max |difference| = {np.nanmax(np.abs(dc - sc)):.3f}")

    matching = pymatching.Matching.from_detector_error_model(circuit.detector_error_model(decompose_errors=True))
    for name, det, obs in (("device", device_det, device_obs), ("stim", stim_det, stim_obs)):
        predicted = matching.decode_batch(det)
        logical_errors = np.any(predicted != obs, axis=1).mean()
        print(f"logical error rate after PyMatching ({name} events): {logical_errors:.4f}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
