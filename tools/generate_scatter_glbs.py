#!/usr/bin/env python3
import argparse
import math
from pathlib import Path

from simple_glb_writer import part, write_glb_parts

OUT_DIR = Path("assets/models/scatter")
GENERATOR_NAME = "Trailhead generate_scatter_glbs.py"
ROUGHNESS_FACTOR = 0.9


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead scatter GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated scatter GLBs.")
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
    return tapered_cylinder(radius, radius, height, segments, wobble)


def tapered_cylinder(bottom_radius, top_radius, height, segments, wobble):
    vertices = []
    for ring_index, y in enumerate((0.0, height)):
        ring_radius = bottom_radius if ring_index == 0 else top_radius
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            ripple = 1.0 + math.sin(angle * 2.0 + float(ring_index) * 0.8) * wobble
            vertices.append((math.cos(angle) * ring_radius * ripple, y, math.sin(angle) * ring_radius * ripple))
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


def tapered_blade(width, height, lean_x, lean_z):
    half_width = width * 0.5
    vertices = [
        (-half_width, 0.0, 0.0),
        (half_width, 0.0, 0.0),
        (-half_width * 0.55, height * 0.55, lean_z * 0.45),
        (half_width * 0.55, height * 0.55, lean_z * 0.45),
        (lean_x, height, lean_z),
    ]
    indices = [0, 1, 3, 0, 3, 2, 2, 3, 4]
    return vertices, indices


def tapered_frond(width, length, arch_height):
    half_width = width * 0.5
    vertices = [
        (-half_width, 0.0, 0.0),
        (half_width, 0.0, 0.0),
        (-half_width * 0.55, arch_height * 0.65, length * 0.55),
        (half_width * 0.55, arch_height * 0.65, length * 0.55),
        (0.0, arch_height, length),
    ]
    indices = [0, 1, 3, 0, 3, 2, 2, 3, 4]
    return vertices, indices


def transformed(mesh, offset, scale=(1.0, 1.0, 1.0), rotation=(0.0, 0.0, 0.0)):
    vertices, indices = mesh
    out = []
    rot_x, rot_y, rot_z = rotation
    cos_x = math.cos(rot_x)
    sin_x = math.sin(rot_x)
    cos_y = math.cos(rot_y)
    sin_y = math.sin(rot_y)
    cos_z = math.cos(rot_z)
    sin_z = math.sin(rot_z)
    for vertex in vertices:
        x = vertex[0] * scale[0]
        y = vertex[1] * scale[1]
        z = vertex[2] * scale[2]
        if rot_x != 0.0:
            y, z = y * cos_x - z * sin_x, y * sin_x + z * cos_x
        if rot_z != 0.0:
            x, y = x * cos_z - y * sin_z, x * sin_z + y * cos_z
        if rot_y != 0.0:
            x, z = x * cos_y + z * sin_y, -x * sin_y + z * cos_y
        out.append((x + offset[0], y + offset[1], z + offset[2]))
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


def grass_tuft():
    blade = tapered_blade(0.035, 0.42, 0.035, 0.055)
    return merge([
        transformed(blade, (-0.08, 0.0, 0.0), (1.0, 1.0, 1.0), (0.0, -0.45, 0.0)),
        transformed(blade, (-0.02, 0.0, -0.06), (0.8, 0.86, 0.8), (0.0, 0.35, 0.0)),
        transformed(blade, (0.06, 0.0, -0.02), (1.05, 0.94, 1.05), (0.0, 1.10, 0.0)),
        transformed(blade, (0.04, 0.0, 0.07), (0.75, 0.70, 0.75), (0.0, 2.45, 0.0)),
        transformed(blade, (-0.045, 0.0, 0.055), (0.70, 0.78, 0.70), (0.0, -1.85, 0.0)),
    ])


def boulder_a():
    return merge([
        tapered_cylinder(0.32, 0.26, 0.20, 14, 0.18),
        transformed(tapered_cylinder(0.21, 0.12, 0.10, 12, 0.12), (-0.06, 0.16, 0.03)),
    ])


def branch_a():
    return merge([
        transformed(cylinder(0.045, 0.95, 10, 0.08), (0.0, 0.05, -0.475), (1.0, 1.0, 1.0), (math.pi * 0.5, 0.0, 0.0)),
        transformed(tapered_cylinder(0.032, 0.018, 0.42, 8, 0.06), (0.10, 0.045, -0.08), (1.0, 1.0, 1.0), (math.pi * 0.5, 0.78, 0.0)),
        transformed(tapered_cylinder(0.024, 0.012, 0.28, 8, 0.05), (-0.12, 0.04, 0.16), (1.0, 1.0, 1.0), (math.pi * 0.5, -0.65, 0.0)),
    ])


def pinecone():
    return merge([
        tapered_cylinder(0.082, 0.068, 0.055, 10, 0.12),
        transformed(tapered_cylinder(0.070, 0.052, 0.055, 10, 0.10), (0.0, 0.045, 0.0)),
        transformed(tapered_cylinder(0.052, 0.026, 0.070, 10, 0.08), (0.0, 0.090, 0.0)),
    ])


def fern_clump():
    frond = tapered_frond(0.09, 0.34, 0.055)
    return merge([
        transformed(frond, (0.0, 0.025, 0.0), (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)),
        transformed(frond, (0.0, 0.025, 0.0), (0.95, 0.95, 0.95), (0.0, 1.30, 0.0)),
        transformed(frond, (0.0, 0.025, 0.0), (0.9, 0.9, 0.9), (0.0, 2.55, 0.0)),
        transformed(frond, (0.0, 0.025, 0.0), (0.85, 0.85, 0.85), (0.0, 3.80, 0.0)),
        transformed(tapered_cylinder(0.035, 0.026, 0.06, 8, 0.04), (0.0, 0.0, 0.0)),
    ])


def cattail():
    leaf = tapered_blade(0.055, 0.50, 0.025, 0.11)
    return merge([
        transformed(cylinder(0.012, 0.58, 8, 0.02), (0.0, 0.0, 0.0)),
        transformed(cylinder(0.035, 0.16, 10, 0.04), (0.0, 0.47, 0.0)),
        transformed(leaf, (-0.025, 0.0, 0.018), (1.0, 0.95, 1.0), (0.0, -0.45, 0.0)),
        transformed(leaf, (0.026, 0.0, -0.018), (0.85, 0.85, 0.85), (0.0, 2.15, 0.0)),
    ])


def trail_blaze():
    return merge([
        transformed(box(0.08, 0.52, 0.045), (0.0, 0.0, 0.0)),
        transformed(box(0.13, 0.08, 0.055), (0.0, 0.33, -0.004)),
    ])


def grass_tuft_parts():
    blade = tapered_blade(0.035, 0.42, 0.035, 0.055)
    return [
        part(merge([
            transformed(blade, (-0.08, 0.0, 0.0), (1.0, 1.0, 1.0), (0.0, -0.45, 0.0)),
            transformed(blade, (0.06, 0.0, -0.02), (1.05, 0.94, 1.05), (0.0, 1.10, 0.0)),
            transformed(blade, (-0.045, 0.0, 0.055), (0.70, 0.78, 0.70), (0.0, -1.85, 0.0)),
        ]), [0.16, 0.32, 0.11, 1.0], "grass_tuft_deep_blades"),
        part(merge([
            transformed(blade, (-0.02, 0.0, -0.06), (0.8, 0.86, 0.8), (0.0, 0.35, 0.0)),
            transformed(blade, (0.04, 0.0, 0.07), (0.75, 0.70, 0.75), (0.0, 2.45, 0.0)),
        ]), [0.30, 0.47, 0.17, 1.0], "grass_tuft_light_blades"),
    ]


def branch_parts():
    return [
        part(transformed(cylinder(0.045, 0.95, 10, 0.08), (0.0, 0.05, -0.475), (1.0, 1.0, 1.0), (math.pi * 0.5, 0.0, 0.0)), [0.22, 0.13, 0.07, 1.0], "branch_main"),
        part(merge([
            transformed(tapered_cylinder(0.032, 0.018, 0.42, 8, 0.06), (0.10, 0.045, -0.08), (1.0, 1.0, 1.0), (math.pi * 0.5, 0.78, 0.0)),
            transformed(tapered_cylinder(0.024, 0.012, 0.28, 8, 0.05), (-0.12, 0.04, 0.16), (1.0, 1.0, 1.0), (math.pi * 0.5, -0.65, 0.0)),
        ]), [0.34, 0.21, 0.11, 1.0], "branch_side"),
    ]


def fern_clump_parts():
    frond = tapered_frond(0.09, 0.34, 0.055)
    return [
        part(merge([
            transformed(frond, (0.0, 0.025, 0.0), (1.0, 1.0, 1.0), (0.0, 0.0, 0.0)),
            transformed(frond, (0.0, 0.025, 0.0), (0.9, 0.9, 0.9), (0.0, 2.55, 0.0)),
        ]), [0.10, 0.29, 0.14, 1.0], "fern_clump_dark_leaves"),
        part(merge([
            transformed(frond, (0.0, 0.025, 0.0), (0.95, 0.95, 0.95), (0.0, 1.30, 0.0)),
            transformed(frond, (0.0, 0.025, 0.0), (0.85, 0.85, 0.85), (0.0, 3.80, 0.0)),
        ]), [0.17, 0.39, 0.18, 1.0], "fern_clump_light_leaves"),
        part(transformed(tapered_cylinder(0.035, 0.026, 0.06, 8, 0.04), (0.0, 0.0, 0.0)), [0.12, 0.18, 0.08, 1.0], "fern_clump_crown"),
    ]


def cattail_parts():
    leaf = tapered_blade(0.055, 0.50, 0.025, 0.11)
    return [
        part(transformed(cylinder(0.012, 0.58, 8, 0.02), (0.0, 0.0, 0.0)), [0.20, 0.32, 0.12, 1.0], "cattail_stem"),
        part(transformed(cylinder(0.035, 0.16, 10, 0.04), (0.0, 0.47, 0.0)), [0.31, 0.20, 0.09, 1.0], "cattail_head"),
        part(merge([
            transformed(leaf, (-0.025, 0.0, 0.018), (1.0, 0.95, 1.0), (0.0, -0.45, 0.0)),
            transformed(leaf, (0.026, 0.0, -0.018), (0.85, 0.85, 0.85), (0.0, 2.15, 0.0)),
        ]), [0.14, 0.30, 0.10, 1.0], "cattail_leaves"),
    ]


def trail_blaze_parts():
    return [
        part(transformed(box(0.08, 0.52, 0.045), (0.0, 0.0, 0.0)), [0.30, 0.18, 0.09, 1.0], "trail_blaze_post"),
        part(transformed(box(0.13, 0.08, 0.055), (0.0, 0.33, -0.004)), [0.82, 0.55, 0.20, 1.0], "trail_blaze_mark"),
    ]


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    assets = [
        ("grass_tuft", grass_tuft_parts()),
        ("boulder_a", [part(boulder_a(), [0.36, 0.36, 0.33, 1.0], "boulder_a")]),
        ("branch_a", branch_parts()),
        ("pinecone", [part(pinecone(), [0.26, 0.15, 0.08, 1.0], "pinecone")]),
        ("fern_clump", fern_clump_parts()),
        ("cattail", cattail_parts()),
        ("trail_blaze", trail_blaze_parts()),
    ]
    for asset_name, parts in assets:
        output_path = out_dir / (asset_name + ".glb")
        write_glb_parts(output_path, asset_name, parts, generator=GENERATOR_NAME, roughness_factor=ROUGHNESS_FACTOR, double_sided=True)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
