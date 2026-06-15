#!/usr/bin/env python3
"""Spike S3: model integer-cell keyed streaming activation determinism.

This is intentionally spike-local. It does not implement the production
streamer; it proves the ordering contract that production streaming must
preserve before touching shipped sim code.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
OUT_PATH = Path(__file__).resolve().parent / "position_keyed_streaming_determinism_results.json"

TILE_SIZE_M = 100.0
MAX_SPEED_MPS = 8.0
TICKS_PER_SECOND = 120
TICKS_PER_TILE = int((TILE_SIZE_M / MAX_SPEED_MPS) * TICKS_PER_SECOND)
ACTIVE_RADIUS = 2
PREFETCH_RADIUS = 3
ACTIVATION_CAP_PER_TICK = 4
ROUTE_CELLS = [(0, 0), (1, -1), (2, -2), (3, -3), (4, -4), (5, -5)]


@dataclass(frozen=True)
class Task:
    cell: tuple[int, int]
    scheduled_tick: int
    ready_tick: int
    worker_index: int
    duration_ticks: int


def main() -> int:
    variants = [
        run_variant("pre_pinned", 0),
        run_variant("streamed_workers_1", 1),
        run_variant("streamed_workers_2", 2),
        run_variant("streamed_workers_8", 8),
    ]
    baseline = variants[0]
    comparisons = [compare_variant(baseline, variant) for variant in variants[1:]]
    passed = all(bool(item["activation_match"]) and bool(item["telemetry_match"]) for item in comparisons)
    result: dict[str, Any] = {
        "spike": "position_keyed_streaming_determinism",
        "hypothesis": (
            "Integer-cell keyed prefetch plus sorted in-physics-tick activation yields identical "
            "activation ticks and telemetry across pre-pinned and streamed worker counts."
        ),
        "inputs": {
            "tile_size_m": TILE_SIZE_M,
            "max_speed_mps": MAX_SPEED_MPS,
            "ticks_per_second": TICKS_PER_SECOND,
            "ticks_per_tile": TICKS_PER_TILE,
            "active_radius": ACTIVE_RADIUS,
            "prefetch_radius": PREFETCH_RADIUS,
            "activation_cap_per_tick": ACTIVATION_CAP_PER_TICK,
            "route_cells": ROUTE_CELLS,
        },
        "variants": variants,
        "comparisons": comparisons,
        "pass": passed,
        "production_recommendation": (
            "Carry this into a Godot S3 implementation by building immutable shape data off-thread, "
            "then activating bodies only from _physics_process in sorted cell order with a bounded "
            "per-tick activation cap. Keep the prefetch budget from S2 and record activation ticks."
        ),
        "limitations": [
            "This is a deterministic proxy, not a RigidBody3D vehicle streaming scene.",
            "It proves activation scheduling and telemetry invariance under out-of-order ready completion.",
            "Production still needs the same check with real HeightMapShape3D resources and raycast/suspension contact.",
        ],
    }
    OUT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "pass": passed,
        "out": str(OUT_PATH.relative_to(ROOT)),
        "comparisons": comparisons,
    }, indent=2, sort_keys=True))
    return 0 if passed else 1


def run_variant(name: str, worker_count: int) -> dict[str, Any]:
    active_cells: set[tuple[int, int]] = set()
    activation_log: list[dict[str, Any]] = []
    telemetry: list[dict[str, Any]] = []
    scheduled: dict[tuple[int, int], Task] = {}
    worker_available: list[int] = [0 for _index in range(max(worker_count, 1))]
    current_tick = 0

    start_cell = ROUTE_CELLS[0]
    prewarm_cells = sorted(radius_cells(start_cell, PREFETCH_RADIUS))
    for cell in prewarm_cells:
        scheduled[cell] = Task(cell, -TICKS_PER_TILE, -1, 0, 0)

    for route_index, center_cell in enumerate(ROUTE_CELLS):
        nominal_tick = route_index * TICKS_PER_TILE
        current_tick = max(current_tick, nominal_tick)
        if route_index > 0:
            schedule_prefetch(center_cell, current_tick - TICKS_PER_TILE, scheduled, worker_available, worker_count)
        required_cells = sorted(radius_cells(center_cell, ACTIVE_RADIUS))
        missing = [cell for cell in required_cells if cell not in active_cells]
        if worker_count > 0 and missing:
            current_tick = max(current_tick, max(scheduled[cell].ready_tick for cell in missing))
        current_tick = activate_missing(name, missing, current_tick, active_cells, activation_log)
        schedule_prefetch(center_cell, current_tick, scheduled, worker_available, worker_count)
        telemetry.append(proxy_telemetry_row(route_index, current_tick, center_cell, active_cells))

    return {
        "name": name,
        "worker_count": worker_count,
        "activation_log": activation_log,
        "activation_by_cell": activation_by_cell(activation_log),
        "telemetry": telemetry,
        "tasks": task_summary(scheduled),
        "out_of_order_ready_events": out_of_order_ready_events(scheduled),
        "stall_ticks": telemetry[-1]["tick"] - ((len(ROUTE_CELLS) - 1) * TICKS_PER_TILE),
    }


def radius_cells(center: tuple[int, int], radius: int) -> set[tuple[int, int]]:
    cells: set[tuple[int, int]] = set()
    cx, cz = center
    for dz in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            cells.add((cx + dx, cz + dz))
    return cells


def schedule_prefetch(
    center_cell: tuple[int, int],
    tick: int,
    scheduled: dict[tuple[int, int], Task],
    worker_available: list[int],
    worker_count: int,
) -> None:
    if worker_count <= 0:
        for cell in sorted(radius_cells(center_cell, PREFETCH_RADIUS)):
            scheduled.setdefault(cell, Task(cell, tick, -1, 0, 0))
        return
    for cell in sorted(radius_cells(center_cell, PREFETCH_RADIUS)):
        if cell in scheduled:
            continue
        worker_index = min(range(worker_count), key=lambda index: (worker_available[index], index))
        start_tick = max(tick, worker_available[worker_index])
        duration = build_duration_ticks(cell)
        ready_tick = start_tick + duration
        worker_available[worker_index] = ready_tick
        scheduled[cell] = Task(cell, tick, ready_tick, worker_index, duration)


def build_duration_ticks(cell: tuple[int, int]) -> int:
    x, z = cell
    hashed = ((x * 73856093) ^ (z * 19349663) ^ 0x5EED) & 0xFFFFFFFF
    return 12 + int(hashed % 71)


def activate_missing(
    variant: str,
    missing: list[tuple[int, int]],
    start_tick: int,
    active_cells: set[tuple[int, int]],
    activation_log: list[dict[str, Any]],
) -> int:
    if not missing:
        return start_tick
    sorted_missing = sorted(missing)
    for index, cell in enumerate(sorted_missing):
        tick = start_tick + index // ACTIVATION_CAP_PER_TICK
        active_cells.add(cell)
        activation_log.append({
            "variant": variant,
            "cell": [cell[0], cell[1]],
            "tick": tick,
            "order_in_tick": index % ACTIVATION_CAP_PER_TICK,
        })
    return start_tick + (len(sorted_missing) - 1) // ACTIVATION_CAP_PER_TICK


def proxy_telemetry_row(
    route_index: int,
    tick: int,
    center_cell: tuple[int, int],
    active_cells: set[tuple[int, int]],
) -> dict[str, Any]:
    x, z = center_cell
    sorted_active = sorted(active_cells)
    return {
        "route_index": route_index,
        "tick": tick,
        "cell": [x, z],
        "position": [x * TILE_SIZE_M, 0.05 + route_index * 0.001, z * TILE_SIZE_M],
        "active_count": len(active_cells),
        "active_hash": active_hash(sorted_active),
        "ray_proxy_height": proxy_height(center_cell),
        "front_probe_cell": [x + 1, z - 1],
    }


def active_hash(cells: list[tuple[int, int]]) -> int:
    value = 1469598103934665603
    for x, z in cells:
        value ^= (x & 0xFFFF) << 16 ^ (z & 0xFFFF)
        value = (value * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return value


def proxy_height(cell: tuple[int, int]) -> float:
    x, z = cell
    return round(((x * 37 + z * 19) % 97) / 970.0, 6)


def activation_by_cell(log: list[dict[str, Any]]) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for entry in log:
        cell = entry["cell"]
        key = f"{cell[0]},{cell[1]}"
        out[key] = {
            "tick": int(entry["tick"]),
            "order_in_tick": int(entry["order_in_tick"]),
        }
    return out


def task_summary(scheduled: dict[tuple[int, int], Task]) -> dict[str, Any]:
    ready_ticks = [task.ready_tick for task in scheduled.values()]
    durations = [task.duration_ticks for task in scheduled.values()]
    return {
        "task_count": len(scheduled),
        "max_ready_tick": max(ready_ticks) if ready_ticks else 0,
        "max_duration_ticks": max(durations) if durations else 0,
    }


def out_of_order_ready_events(scheduled: dict[tuple[int, int], Task]) -> int:
    ordered = sorted(scheduled.values(), key=lambda task: (task.scheduled_tick, task.cell))
    ready_ticks = [task.ready_tick for task in ordered]
    count = 0
    for index in range(1, len(ready_ticks)):
        if ready_ticks[index] < ready_ticks[index - 1]:
            count += 1
    return count


def compare_variant(baseline: dict[str, Any], variant: dict[str, Any]) -> dict[str, Any]:
    activation_match = baseline["activation_by_cell"] == variant["activation_by_cell"]
    telemetry_match = baseline["telemetry"] == variant["telemetry"]
    return {
        "variant": variant["name"],
        "activation_match": activation_match,
        "telemetry_match": telemetry_match,
        "baseline_activation_count": len(baseline["activation_log"]),
        "variant_activation_count": len(variant["activation_log"]),
        "out_of_order_ready_events": variant["out_of_order_ready_events"],
        "stall_ticks": variant["stall_ticks"],
    }


if __name__ == "__main__":
    raise SystemExit(main())
