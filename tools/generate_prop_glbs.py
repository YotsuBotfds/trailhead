#!/usr/bin/env python3
import argparse
import math
from pathlib import Path

from simple_glb_writer import part, write_glb_parts

OUT_DIR = Path("assets/models/props")
GENERATOR_NAME = "Trailhead generate_prop_glbs.py"
ROUGHNESS_FACTOR = 0.88


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead prop GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated prop GLBs.")
    return parser.parse_args()


def box(width, height, depth):
    x = width * 0.5
    z = depth * 0.5
    vertices = [
        (-x, 0.0, -z), (x, 0.0, -z), (x, height, -z), (-x, height, -z),
        (-x, 0.0, z), (x, 0.0, z), (x, height, z), (-x, height, z),
    ]
    indices = [
        0, 1, 2, 0, 2, 3,
        4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1,
        3, 2, 6, 3, 6, 7,
        1, 5, 6, 1, 6, 2,
        0, 3, 7, 0, 7, 4,
    ]
    return vertices, indices


def cylinder(radius, height, segments, wobble):
    vertices = []
    for y in (0.0, height):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            ripple = 1.0 + math.sin(angle * 3.0) * wobble
            vertices.append((math.cos(angle) * radius * ripple, y, math.sin(angle) * radius * ripple))
    vertices.append((0.0, 0.0, 0.0))
    vertices.append((0.0, height, 0.0))
    bottom_center = len(vertices) - 2
    top_center = len(vertices) - 1
    indices = []
    for segment in range(segments):
        next_segment = (segment + 1) % segments
        bottom_a = segment
        bottom_b = next_segment
        top_a = segment + segments
        top_b = next_segment + segments
        indices.extend([bottom_a, bottom_b, top_b, bottom_a, top_b, top_a])
        indices.extend([bottom_center, bottom_a, bottom_b])
        indices.extend([top_center, top_b, top_a])
    return vertices, indices


def transformed(mesh, offset, scale=(1.0, 1.0, 1.0)):
    vertices, indices = mesh
    out = []
    for vertex in vertices:
        out.append((
            vertex[0] * scale[0] + offset[0],
            vertex[1] * scale[1] + offset[1],
            vertex[2] * scale[2] + offset[2],
        ))
    return out, indices


def merge(meshes):
    vertices = []
    indices = []
    for mesh_vertices, mesh_indices in meshes:
        base_index = len(vertices)
        vertices.extend(mesh_vertices)
        for index in mesh_indices:
            indices.append(index + base_index)
    return vertices, indices


def trail_sign():
    return merge([
        transformed(box(0.08, 1.0, 0.08), (-0.38, 0.0, 0.0)),
        transformed(box(0.08, 1.0, 0.08), (0.38, 0.0, 0.0)),
        transformed(box(0.9, 0.26, 0.08), (0.0, 0.68, 0.0)),
        transformed(box(0.75, 0.18, 0.06), (0.0, 0.38, 0.01)),
    ])


def kiosk():
    return merge([
        transformed(box(0.08, 1.22, 0.08), (-0.46, 0.0, 0.0)),
        transformed(box(0.08, 1.22, 0.08), (0.46, 0.0, 0.0)),
        transformed(box(0.98, 0.58, 0.07), (0.0, 0.52, 0.0)),
        transformed(box(1.15, 0.08, 0.26), (0.0, 1.12, 0.0)),
        transformed(box(0.86, 0.09, 0.06), (0.0, 0.20, -0.01)),
    ])


def mile_marker():
    return merge([
        transformed(cylinder(0.045, 0.58, 12, 0.02), (0.0, 0.0, 0.0)),
        transformed(box(0.22, 0.18, 0.055), (0.0, 0.48, 0.0)),
        transformed(box(0.16, 0.045, 0.06), (0.0, 0.66, 0.0)),
    ])


def park_bench():
    return merge([
        transformed(box(1.15, 0.055, 0.18), (0.0, 0.42, -0.12)),
        transformed(box(1.15, 0.055, 0.18), (0.0, 0.42, 0.12)),
        transformed(box(1.15, 0.06, 0.14), (0.0, 0.72, 0.28)),
        transformed(box(1.15, 0.06, 0.14), (0.0, 0.54, 0.32)),
        transformed(box(0.075, 0.42, 0.075), (-0.44, 0.0, -0.20)),
        transformed(box(0.075, 0.42, 0.075), (0.44, 0.0, -0.20)),
        transformed(box(0.075, 0.56, 0.075), (-0.44, 0.0, 0.32)),
        transformed(box(0.075, 0.56, 0.075), (0.44, 0.0, 0.32)),
    ])


def carabiner():
    return merge([
        transformed(box(0.035, 0.012, 0.22), (-0.06, 0.0, 0.0)),
        transformed(box(0.035, 0.012, 0.22), (0.06, 0.0, 0.0)),
        transformed(box(0.16, 0.012, 0.035), (0.0, 0.0, -0.095)),
        transformed(box(0.16, 0.012, 0.035), (0.0, 0.0, 0.095)),
        transformed(box(0.024, 0.018, 0.15), (0.028, 0.018, 0.0)),
    ])


def bottle_cap():
    return merge([
        cylinder(0.075, 0.035, 20, 0.035),
        transformed(box(0.018, 0.02, 0.018), (0.075, 0.035, 0.0)),
        transformed(box(0.018, 0.02, 0.018), (-0.075, 0.035, 0.0)),
        transformed(box(0.018, 0.02, 0.018), (0.0, 0.035, 0.075)),
        transformed(box(0.018, 0.02, 0.018), (0.0, 0.035, -0.075)),
    ])


def picnic_table():
    return merge([
        transformed(box(1.25, 0.08, 0.42), (0.0, 0.52, 0.0)),
        transformed(box(1.12, 0.07, 0.18), (0.0, 0.32, -0.42)),
        transformed(box(1.12, 0.07, 0.18), (0.0, 0.32, 0.42)),
        transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, -0.16)),
        transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, -0.16)),
        transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, 0.16)),
        transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, 0.16)),
    ])


def old_cedar_stump():
    trunk = transformed(cylinder(0.42, 1.15, 18, 0.12), (0.0, 0.0, 0.0))
    return merge([
        trunk,
        transformed(box(0.95, 0.12, 0.18), (0.0, 0.02, 0.44)),
        transformed(box(0.8, 0.10, 0.16), (0.34, 0.02, -0.36)),
        transformed(box(0.7, 0.10, 0.16), (-0.4, 0.02, -0.28)),
    ])


def fire_ring():
    stones = []
    for index in range(12):
        angle = math.tau * float(index) / 12.0
        stones.append(transformed(
            cylinder(0.075, 0.085, 10, 0.10),
            (math.cos(angle) * 0.36, 0.0, math.sin(angle) * 0.36),
            (1.0, 0.75, 1.0),
        ))
    return merge(stones)


def hiking_boot():
    return merge([
        transformed(box(0.46, 0.08, 0.18), (0.0, 0.0, 0.0)),
        transformed(box(0.34, 0.18, 0.17), (-0.03, 0.06, 0.0)),
        transformed(box(0.15, 0.24, 0.16), (-0.2, 0.16, 0.0)),
        transformed(box(0.18, 0.08, 0.16), (0.2, 0.08, 0.0)),
    ])


def water_bottle():
    return merge([
        transformed(cylinder(0.08, 0.42, 16, 0.02), (0.0, 0.0, 0.0)),
        transformed(cylinder(0.055, 0.08, 12, 0.01), (0.0, 0.42, 0.0)),
        transformed(cylinder(0.06, 0.035, 12, 0.0), (0.0, 0.50, 0.0)),
    ])


def trail_sign_parts():
    return [
        part(merge([
            transformed(box(0.08, 1.0, 0.08), (-0.38, 0.0, 0.0)),
            transformed(box(0.08, 1.0, 0.08), (0.38, 0.0, 0.0)),
        ]), [0.28, 0.17, 0.09, 1.0], "trail_sign_posts"),
        part(merge([
            transformed(box(0.9, 0.26, 0.08), (0.0, 0.68, 0.0)),
            transformed(box(0.75, 0.18, 0.06), (0.0, 0.38, 0.01)),
        ]), [0.55, 0.38, 0.20, 1.0], "trail_sign_boards"),
    ]


def kiosk_parts():
    return [
        part(merge([
            transformed(box(0.08, 1.22, 0.08), (-0.46, 0.0, 0.0)),
            transformed(box(0.08, 1.22, 0.08), (0.46, 0.0, 0.0)),
        ]), [0.26, 0.16, 0.08, 1.0], "kiosk_posts"),
        part(transformed(box(0.98, 0.58, 0.07), (0.0, 0.52, 0.0)), [0.45, 0.30, 0.16, 1.0], "kiosk_panel"),
        part(merge([
            transformed(box(1.15, 0.08, 0.26), (0.0, 1.12, 0.0)),
            transformed(box(0.86, 0.09, 0.06), (0.0, 0.20, -0.01)),
        ]), [0.18, 0.12, 0.07, 1.0], "kiosk_roof_shelf"),
    ]


def mile_marker_parts():
    return [
        part(transformed(cylinder(0.045, 0.58, 12, 0.02), (0.0, 0.0, 0.0)), [0.34, 0.27, 0.18, 1.0], "mile_marker_post"),
        part(merge([
            transformed(box(0.22, 0.18, 0.055), (0.0, 0.48, 0.0)),
            transformed(box(0.16, 0.045, 0.06), (0.0, 0.66, 0.0)),
        ]), [0.64, 0.54, 0.36, 1.0], "mile_marker_face"),
    ]


def park_bench_parts():
    return [
        part(merge([
            transformed(box(1.15, 0.055, 0.18), (0.0, 0.42, -0.12)),
            transformed(box(1.15, 0.055, 0.18), (0.0, 0.42, 0.12)),
            transformed(box(1.15, 0.06, 0.14), (0.0, 0.72, 0.28)),
            transformed(box(1.15, 0.06, 0.14), (0.0, 0.54, 0.32)),
        ]), [0.43, 0.27, 0.15, 1.0], "park_bench_planks"),
        part(merge([
            transformed(box(0.075, 0.42, 0.075), (-0.44, 0.0, -0.20)),
            transformed(box(0.075, 0.42, 0.075), (0.44, 0.0, -0.20)),
            transformed(box(0.075, 0.56, 0.075), (-0.44, 0.0, 0.32)),
            transformed(box(0.075, 0.56, 0.075), (0.44, 0.0, 0.32)),
        ]), [0.18, 0.13, 0.09, 1.0], "park_bench_legs"),
    ]


def carabiner_parts():
    return [
        part(merge([
            transformed(box(0.035, 0.012, 0.22), (-0.06, 0.0, 0.0)),
            transformed(box(0.035, 0.012, 0.22), (0.06, 0.0, 0.0)),
            transformed(box(0.16, 0.012, 0.035), (0.0, 0.0, -0.095)),
            transformed(box(0.16, 0.012, 0.035), (0.0, 0.0, 0.095)),
        ]), [0.08, 0.09, 0.09, 1.0], "carabiner_frame"),
        part(transformed(box(0.024, 0.018, 0.15), (0.028, 0.018, 0.0)), [0.56, 0.50, 0.38, 1.0], "carabiner_gate"),
    ]


def bottle_cap_parts():
    return [
        part(cylinder(0.075, 0.035, 20, 0.035), [0.56, 0.10, 0.08, 1.0], "bottle_cap_shell"),
        part(merge([
            transformed(box(0.018, 0.02, 0.018), (0.075, 0.035, 0.0)),
            transformed(box(0.018, 0.02, 0.018), (-0.075, 0.035, 0.0)),
            transformed(box(0.018, 0.02, 0.018), (0.0, 0.035, 0.075)),
            transformed(box(0.018, 0.02, 0.018), (0.0, 0.035, -0.075)),
        ]), [0.78, 0.68, 0.50, 1.0], "bottle_cap_ridges"),
    ]


def picnic_table_parts():
    return [
        part(merge([
            transformed(box(1.25, 0.08, 0.42), (0.0, 0.52, 0.0)),
            transformed(box(1.12, 0.07, 0.18), (0.0, 0.32, -0.42)),
            transformed(box(1.12, 0.07, 0.18), (0.0, 0.32, 0.42)),
        ]), [0.48, 0.30, 0.16, 1.0], "picnic_table_planks"),
        part(merge([
            transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, -0.16)),
            transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, -0.16)),
            transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, 0.16)),
            transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, 0.16)),
        ]), [0.25, 0.16, 0.08, 1.0], "picnic_table_legs"),
    ]


def old_cedar_stump_parts():
    return [
        part(transformed(cylinder(0.42, 1.15, 18, 0.12), (0.0, 0.0, 0.0)), [0.34, 0.20, 0.10, 1.0], "old_cedar_stump_trunk"),
        part(merge([
            transformed(box(0.95, 0.12, 0.18), (0.0, 0.02, 0.44)),
            transformed(box(0.8, 0.10, 0.16), (0.34, 0.02, -0.36)),
            transformed(box(0.7, 0.10, 0.16), (-0.4, 0.02, -0.28)),
        ]), [0.18, 0.11, 0.06, 1.0], "old_cedar_stump_roots"),
    ]


def fire_ring_parts():
    stones = []
    for index in range(12):
        angle = math.tau * float(index) / 12.0
        stones.append(transformed(
            cylinder(0.075, 0.085, 10, 0.10),
            (math.cos(angle) * 0.36, 0.0, math.sin(angle) * 0.36),
            (1.0, 0.75, 1.0),
        ))
    return [
        part(merge(stones), [0.34, 0.33, 0.29, 1.0], "fire_ring_stones"),
        part(transformed(cylinder(0.24, 0.015, 14, 0.02), (0.0, 0.0, 0.0)), [0.12, 0.11, 0.10, 1.0], "fire_ring_ash"),
    ]


def hiking_boot_parts():
    return [
        part(merge([
            transformed(box(0.46, 0.08, 0.18), (0.0, 0.0, 0.0)),
            transformed(box(0.18, 0.08, 0.16), (0.2, 0.08, 0.0)),
        ]), [0.07, 0.05, 0.035, 1.0], "hiking_boot_sole_toe"),
        part(merge([
            transformed(box(0.34, 0.18, 0.17), (-0.03, 0.06, 0.0)),
            transformed(box(0.15, 0.24, 0.16), (-0.2, 0.16, 0.0)),
        ]), [0.28, 0.16, 0.08, 1.0], "hiking_boot_upper"),
    ]


def water_bottle_parts():
    return [
        part(transformed(cylinder(0.08, 0.42, 16, 0.02), (0.0, 0.0, 0.0)), [0.16, 0.42, 0.58, 1.0], "water_bottle_body"),
        part(transformed(cylinder(0.055, 0.08, 12, 0.01), (0.0, 0.42, 0.0)), [0.80, 0.86, 0.86, 1.0], "water_bottle_neck"),
        part(transformed(cylinder(0.06, 0.035, 12, 0.0), (0.0, 0.50, 0.0)), [0.08, 0.18, 0.26, 1.0], "water_bottle_cap"),
    ]


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    assets = [
        ("trail_sign", trail_sign_parts()),
        ("kiosk", kiosk_parts()),
        ("mile_marker", mile_marker_parts()),
        ("park_bench", park_bench_parts()),
        ("carabiner", carabiner_parts()),
        ("bottle_cap", bottle_cap_parts()),
        ("picnic_table", picnic_table_parts()),
        ("old_cedar_stump", old_cedar_stump_parts()),
        ("fire_ring", fire_ring_parts()),
        ("hiking_boot", hiking_boot_parts()),
        ("water_bottle", water_bottle_parts()),
    ]
    for asset_name, parts in assets:
        output_path = out_dir / (asset_name + ".glb")
        write_glb_parts(output_path, asset_name, parts, generator=GENERATOR_NAME, roughness_factor=ROUGHNESS_FACTOR)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
