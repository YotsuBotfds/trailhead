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


def parse_near(spec):
    parts = spec.split(":", 2)
    if len(parts) != 3:
        raise argparse.ArgumentTypeError(f"expected name:expected:tolerance, got {spec}")
    name, expected, tolerance = parts
    if not name:
        raise argparse.ArgumentTypeError(f"missing name in {spec}")
    try:
        return name, float(expected), float(tolerance)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid expected/tolerance in {spec}") from exc


def sequence_contains(actual, expected):
    expected_index = 0
    for value in actual:
        if expected_index < len(expected) and value == expected[expected_index]:
            expected_index += 1
    return expected_index == len(expected)


def nested_value(values, dotted_name):
    current = values
    for part in dotted_name.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def load_json(path):
    try:
        text = path.read_text()
    except OSError as exc:
        raise ValueError(f"missing or unreadable input: {exc}") from exc
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"bad JSON at line {exc.lineno} column {exc.colno}: {exc.msg}") from exc
    if not isinstance(data, dict):
        raise ValueError("JSON root must be an object")
    return data


def as_number(value, label, errors):
    try:
        return float(value)
    except (TypeError, ValueError):
        errors.append(f"{label} is not numeric: {value!r}")
        return None


def main():
    parser = argparse.ArgumentParser(description="Assert selected metrics from a Trailhead sim JSON output.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--surface", action="append", default=[], type=parse_minimum, metavar="SURFACE:MIN_TICKS")
    parser.add_argument("--surface-sequence", default="", metavar="SURFACE_A,SURFACE_B")
    parser.add_argument("--landmark", action="append", default=[])
    parser.add_argument("--predicate", action="append", default=[])
    parser.add_argument("--metric-min", action="append", default=[], type=parse_minimum, metavar="METRIC:MIN_VALUE")
    parser.add_argument("--metric-near", action="append", default=[], type=parse_near, metavar="METRIC:EXPECTED:TOLERANCE")
    parser.add_argument("--source-min", action="append", default=[], type=parse_minimum, metavar="SOURCE:MIN_VALUE")
    args = parser.parse_args()

    errors = []
    try:
        data = load_json(args.path)
    except ValueError as exc:
        print(f"fail: {args.path}")
        print(f"- {exc}")
        return 1

    if data.get("result") != "pass":
        errors.append(f"expected result pass, got {data.get('result')}")

    metrics = data.get("metrics", {})
    if not isinstance(metrics, dict):
        errors.append("metrics is not an object")
        metrics = {}
    surface_ticks = metrics.get("surface_contact_ticks", {})
    if not isinstance(surface_ticks, dict):
        errors.append("metrics.surface_contact_ticks is not an object")
        surface_ticks = {}
    for surface_id, minimum in args.surface:
        actual = as_number(surface_ticks.get(surface_id, 0.0), f"surface {surface_id} ticks", errors)
        if actual is None:
            continue
        if actual < minimum:
            errors.append(f"surface {surface_id} ticks {actual:g} < {minimum:g}")

    if args.surface_sequence:
        expected = [value for value in args.surface_sequence.split(",") if value]
        actual_sequence = metrics.get("surface_event_sequence", [])
        if not isinstance(actual_sequence, list):
            actual_sequence = []
            errors.append("metrics.surface_event_sequence is not an array")
        if not sequence_contains(actual_sequence, expected):
            errors.append(f"surface sequence {actual_sequence} does not contain {expected}")

    landmark_sequence = metrics.get("landmark_event_sequence", [])
    if not isinstance(landmark_sequence, list):
        landmark_sequence = []
        errors.append("metrics.landmark_event_sequence is not an array")
    for landmark_id in args.landmark:
        if landmark_id not in landmark_sequence:
            errors.append(f"missing landmark event {landmark_id}; saw {landmark_sequence}")

    predicates = data.get("predicates", {})
    if not isinstance(predicates, dict):
        predicates = {}
        errors.append("predicates is not an object")
    for predicate_name in args.predicate:
        if predicate_name not in predicates:
            errors.append(f"missing predicate {predicate_name}")
            continue
        actual_predicate = predicates[predicate_name]
        if actual_predicate is not True:
            errors.append(f"predicate {predicate_name} was not true; got {actual_predicate!r}")

    for metric_name, minimum in args.metric_min:
        actual_value = nested_value(metrics, metric_name)
        if actual_value is None:
            errors.append(f"missing metric {metric_name}")
            continue
        actual = as_number(actual_value, f"metric {metric_name}", errors)
        if actual is None:
            continue
        if actual < minimum:
            errors.append(f"metric {metric_name} {actual:g} < {minimum:g}")

    for metric_name, expected, tolerance in args.metric_near:
        actual_value = nested_value(metrics, metric_name)
        if actual_value is None:
            errors.append(f"missing metric {metric_name}")
            continue
        actual = as_number(actual_value, f"metric {metric_name}", errors)
        if actual is None:
            continue
        delta = abs(actual - expected)
        if delta > tolerance:
            errors.append(f"metric {metric_name} delta {delta:g} > {tolerance:g} (expected {expected:g}, got {actual:g})")

    source_counts = metrics.get("surface_source_counts", {})
    if not isinstance(source_counts, dict):
        errors.append("metrics.surface_source_counts is not an object")
        source_counts = {}
    for source_id, minimum in args.source_min:
        actual = as_number(source_counts.get(source_id, 0.0), f"surface source {source_id} count", errors)
        if actual is None:
            continue
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
