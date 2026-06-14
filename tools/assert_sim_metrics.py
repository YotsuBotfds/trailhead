#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path


def parse_minimum(spec):
    if ":" not in spec:
        raise argparse.ArgumentTypeError(f"expected name:min, got {spec}")
    name, value = spec.split(":", 1)
    if not name:
        raise argparse.ArgumentTypeError(f"missing name in {spec}")
    try:
        return name, float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid minimum in {spec}") from exc


def sequence_contains(actual, expected):
    expected_index = 0
    for value in actual:
        if expected_index < len(expected) and value == expected[expected_index]:
            expected_index += 1
    return expected_index == len(expected)


def main():
    parser = argparse.ArgumentParser(description="Assert selected metrics from a Trailhead sim JSON output.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--surface", action="append", default=[], type=parse_minimum, metavar="SURFACE:MIN_TICKS")
    parser.add_argument("--surface-sequence", default="", metavar="SURFACE_A,SURFACE_B")
    parser.add_argument("--landmark", action="append", default=[])
    parser.add_argument("--metric-min", action="append", default=[], type=parse_minimum, metavar="METRIC:MIN_VALUE")
    parser.add_argument("--source-min", action="append", default=[], type=parse_minimum, metavar="SOURCE:MIN_VALUE")
    args = parser.parse_args()

    data = json.loads(args.path.read_text())
    errors = []
    if data.get("result") != "pass":
        errors.append(f"expected result pass, got {data.get('result')}")

    metrics = data.get("metrics", {})
    surface_ticks = metrics.get("surface_contact_ticks", {})
    for surface_id, minimum in args.surface:
        actual = float(surface_ticks.get(surface_id, 0.0))
        if actual < minimum:
            errors.append(f"surface {surface_id} ticks {actual:g} < {minimum:g}")

    if args.surface_sequence:
        expected = [value for value in args.surface_sequence.split(",") if value]
        actual_sequence = metrics.get("surface_event_sequence", [])
        if not sequence_contains(actual_sequence, expected):
            errors.append(f"surface sequence {actual_sequence} does not contain {expected}")

    landmark_sequence = metrics.get("landmark_event_sequence", [])
    for landmark_id in args.landmark:
        if landmark_id not in landmark_sequence:
            errors.append(f"missing landmark event {landmark_id}; saw {landmark_sequence}")

    for metric_name, minimum in args.metric_min:
        actual_value = metrics.get(metric_name)
        if actual_value is None:
            errors.append(f"missing metric {metric_name}")
            continue
        actual = float(actual_value)
        if actual < minimum:
            errors.append(f"metric {metric_name} {actual:g} < {minimum:g}")

    source_counts = metrics.get("surface_source_counts", {})
    for source_id, minimum in args.source_min:
        actual = float(source_counts.get(source_id, 0.0))
        if actual < minimum:
            errors.append(f"surface source {source_id} count {actual:g} < {minimum:g}")

    if errors:
        print(f"fail: {args.path}")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"ok: {args.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
