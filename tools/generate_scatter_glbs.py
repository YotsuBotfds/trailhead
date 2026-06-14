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
    vertices = []
    for y in (0.0, height):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            ripple = 1.0 + math.sin(angle * 2.0) * wobble
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


def grass_tuft():
    blade = box(0.025, 0.42, 0.025)
    return merge([
        transformed(blade, (-0.08, 0.0, 0.0), (1.0, 1.0, 1.0)),
        transformed(blade, (0.0, 0.0, -0.05), (1.0, 0.82, 1.0)),
        transformed(blade, (0.08, 0.0, 0.02), (1.0, 0.95, 1.0)),
        transformed(blade, (0.02, 0.0, 0.08), (1.0, 0.72, 1.0)),
    ])


def boulder_a():
    return cylinder(0.32, 0.24, 12, 0.18)


def branch_a():
    return merge([
        transformed(box(0.12, 0.08, 0.95), (0.0, 0.0, 0.0)),
        transformed(box(0.08, 0.06, 0.38), (0.23, 0.02, 0.18)),
    ])


def pinecone():
    return cylinder(0.08, 0.18, 9, 0.1)


def fern_clump():
    leaf = box(0.06, 0.018, 0.34)
    return merge([
        transformed(leaf, (-0.10, 0.03, 0.00), (1.0, 1.0, 1.0)),
        transformed(leaf, (0.10, 0.03, 0.00), (1.0, 1.0, 1.0)),
        transformed(leaf, (0.00, 0.04, -0.10), (0.9, 1.0, 1.0)),
        transformed(leaf, (0.00, 0.04, 0.10), (0.9, 1.0, 1.0)),
        transformed(box(0.05, 0.07, 0.05), (0.0, 0.0, 0.0)),
    ])


def cattail():
    return merge([
        transformed(cylinder(0.012, 0.58, 8, 0.02), (0.0, 0.0, 0.0)),
        transformed(cylinder(0.035, 0.16, 10, 0.04), (0.0, 0.47, 0.0)),
    ])


def trail_blaze():
    return merge([
        transformed(box(0.08, 0.52, 0.045), (0.0, 0.0, 0.0)),
        transformed(box(0.13, 0.08, 0.055), (0.0, 0.33, -0.004)),
    ])


def grass_tuft_parts():
    blade = box(0.025, 0.42, 0.025)
    return [
        part(merge([
            transformed(blade, (-0.08, 0.0, 0.0), (1.0, 1.0, 1.0)),
            transformed(blade, (0.08, 0.0, 0.02), (1.0, 0.95, 1.0)),
        ]), [0.18, 0.34, 0.12, 1.0], "grass_tuft_deep_blades"),
        part(merge([
            transformed(blade, (0.0, 0.0, -0.05), (1.0, 0.82, 1.0)),
            transformed(blade, (0.02, 0.0, 0.08), (1.0, 0.72, 1.0)),
        ]), [0.30, 0.46, 0.16, 1.0], "grass_tuft_light_blades"),
    ]


def branch_parts():
    return [
        part(transformed(box(0.12, 0.08, 0.95), (0.0, 0.0, 0.0)), [0.22, 0.13, 0.07, 1.0], "branch_main"),
        part(transformed(box(0.08, 0.06, 0.38), (0.23, 0.02, 0.18)), [0.34, 0.21, 0.11, 1.0], "branch_side"),
    ]


def fern_clump_parts():
    leaf = box(0.06, 0.018, 0.34)
    return [
        part(merge([
            transformed(leaf, (-0.10, 0.03, 0.00), (1.0, 1.0, 1.0)),
            transformed(leaf, (0.00, 0.04, -0.10), (0.9, 1.0, 1.0)),
        ]), [0.10, 0.29, 0.14, 1.0], "fern_clump_dark_leaves"),
        part(merge([
            transformed(leaf, (0.10, 0.03, 0.00), (1.0, 1.0, 1.0)),
            transformed(leaf, (0.00, 0.04, 0.10), (0.9, 1.0, 1.0)),
        ]), [0.17, 0.39, 0.18, 1.0], "fern_clump_light_leaves"),
        part(transformed(box(0.05, 0.07, 0.05), (0.0, 0.0, 0.0)), [0.12, 0.18, 0.08, 1.0], "fern_clump_crown"),
    ]


def cattail_parts():
    return [
        part(transformed(cylinder(0.012, 0.58, 8, 0.02), (0.0, 0.0, 0.0)), [0.20, 0.32, 0.12, 1.0], "cattail_stem"),
        part(transformed(cylinder(0.035, 0.16, 10, 0.04), (0.0, 0.47, 0.0)), [0.31, 0.20, 0.09, 1.0], "cattail_head"),
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
        write_glb_parts(output_path, asset_name, parts, generator=GENERATOR_NAME, roughness_factor=ROUGHNESS_FACTOR)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
