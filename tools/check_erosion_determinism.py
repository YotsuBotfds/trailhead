#!/usr/bin/env python3
from __future__ import annotations

import sys

import numpy as np

from erosion import ErosionConfig, build_eroded_heightfield, resample_heightfield, sample_heightfield


EXPECTED_NUMPY_VERSION = "2.4.6"
BOUNDS = ((-5.5, -10.6), (5.5, 1.6))
SEED = 20260615


def main() -> int:
    if np.__version__ != EXPECTED_NUMPY_VERSION:
        print(f"fail: numpy {np.__version__} != {EXPECTED_NUMPY_VERSION}", file=sys.stderr)
        return 1

    config = ErosionConfig(
        hydraulic_droplets=512,
        hydraulic_max_steps=18,
        thermal_iterations=4,
    )
    first = build_eroded_heightfield(96, 112, BOUNDS, seed=SEED, config=config)
    second = build_eroded_heightfield(96, 112, BOUNDS, seed=SEED, config=config)
    if not np.array_equal(first, second):
        print("fail: eroded heightfield is not deterministic for identical seed/config", file=sys.stderr)
        return 1

    third = build_eroded_heightfield(96, 112, BOUNDS, seed=SEED + 1, config=config)
    if np.array_equal(first, third):
        print("fail: eroded heightfield did not change for a different seed", file=sys.stderr)
        return 1

    samples = sample_heightfield(first, BOUNDS, np.array([-4.0, 0.0, 4.0]), np.array([-9.0, -5.0, 0.0]))
    if samples.shape != (3,) or not np.isfinite(samples).all():
        print("fail: erosion sampler returned invalid samples", file=sys.stderr)
        return 1

    resized = resample_heightfield(first, BOUNDS, 17, 19)
    if resized.shape != (19, 17) or resized.dtype != np.float32:
        print("fail: erosion resample returned invalid shape/dtype", file=sys.stderr)
        return 1

    print("ok: erosion heightfield determinism")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
