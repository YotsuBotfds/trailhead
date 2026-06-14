#!/usr/bin/env python3
import argparse
import math
from pathlib import Path

from simple_glb_writer import part, write_glb_parts

OUT_DIR = Path("assets/models/features")
GENERATOR_NAME = "Trailhead generate_feature_glbs.py"
ROUGHNESS_FACTOR = 0.85


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead feature GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated feature GLBs.")
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


def hard_box(width, height, depth):
    x = width * 0.5
    z = depth * 0.5
    corners = [
        (-x, 0.0, -z), (x, 0.0, -z), (x, height, -z), (-x, height, -z),
        (-x, 0.0, z), (x, 0.0, z), (x, height, z), (-x, height, z),
    ]
    faces = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (3, 2, 6, 7),
        (1, 5, 6, 2),
        (0, 3, 7, 4),
    ]
    vertices = []
    indices = []
    for face in faces:
        base = len(vertices)
        vertices.extend(corners[index] for index in face)
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    return vertices, indices


def wedge(width, height, depth):
    x = width * 0.5
    z = depth * 0.5
    vertices = [
        (-x, 0.0, -z), (x, 0.0, -z), (-x, height, z), (x, height, z),
        (-x, 0.0, z), (x, 0.0, z),
    ]
    indices = [
        0, 1, 3, 0, 3, 2,
        4, 2, 3, 4, 3, 5,
        0, 4, 5, 0, 5, 1,
        0, 2, 4,
        1, 5, 3,
    ]
    return vertices, indices


def cylinder(radius, height, segments):
    vertices = []
    for y in (0.0, height):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            wobble = 1.0 + (0.08 if segment % 2 == 0 else -0.04)
            vertices.append((math.cos(angle) * radius * wobble, y, math.sin(angle) * radius * wobble))
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


def hard_capped_cylinder(radius, height, segments):
    side_vertices = []
    bottom_cap_vertices = []
    top_cap_vertices = []
    for y in (0.0, height):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            wobble = 1.0 + (0.08 if segment % 2 == 0 else -0.04)
            side_vertices.append((math.cos(angle) * radius * wobble, y, math.sin(angle) * radius * wobble))
    for segment in range(segments):
        angle = math.tau * float(segment) / float(segments)
        wobble = 1.0 + (0.08 if segment % 2 == 0 else -0.04)
        bottom_cap_vertices.append((math.cos(angle) * radius * wobble, 0.0, math.sin(angle) * radius * wobble))
        top_cap_vertices.append((math.cos(angle) * radius * wobble, height, math.sin(angle) * radius * wobble))
    vertices = side_vertices + bottom_cap_vertices + top_cap_vertices
    bottom_center = len(vertices)
    top_center = bottom_center + 1
    vertices.append((0.0, 0.0, 0.0))
    vertices.append((0.0, height, 0.0))
    bottom_cap_start = segments * 2
    top_cap_start = bottom_cap_start + segments
    indices = []
    for segment in range(segments):
        next_segment = (segment + 1) % segments
        bottom_a = segment
        bottom_b = next_segment
        top_a = segment + segments
        top_b = next_segment + segments
        indices.extend([bottom_a, bottom_b, top_b, bottom_a, top_b, top_a])
        indices.extend([bottom_center, bottom_cap_start + segment, bottom_cap_start + next_segment])
        indices.extend([top_center, top_cap_start + next_segment, top_cap_start + segment])
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


def pipe(radius, length, segments):
    vertices = []
    for z in (-length * 0.5, length * 0.5):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            vertices.append((math.cos(angle) * radius, radius + math.sin(angle) * radius, z))
    indices = []
    for segment in range(segments):
        next_segment = (segment + 1) % segments
        a0 = segment
        b0 = next_segment
        a1 = segment + segments
        b1 = next_segment + segments
        indices.extend([a0, b0, b1, a0, b1, a1])
    return vertices, indices


def boardwalk_segment_parts():
    plank_offsets = [-0.31, 0.0, 0.31]
    planks = []
    worn_edges = []
    nail_heads = []
    for index, x_offset in enumerate(plank_offsets):
        planks.append(transformed(box(0.285, 0.044, 0.205), (x_offset, 0.0, 0.0)))
        worn_edges.append(transformed(box(0.24, 0.006, 0.026), (x_offset, 0.046, -0.080 + float(index % 2) * 0.010)))
        worn_edges.append(transformed(box(0.20, 0.006, 0.024), (x_offset + 0.018, 0.046, 0.074 - float(index % 2) * 0.012)))
        for z_offset in [-0.074, 0.074]:
            nail_heads.append(transformed(box(0.024, 0.007, 0.018), (x_offset - 0.095, 0.052, z_offset)))
            nail_heads.append(transformed(box(0.024, 0.007, 0.018), (x_offset + 0.095, 0.052, z_offset)))
    return [
        part(merge(planks), [0.44, 0.28, 0.14, 1.0], "boardwalk_segment_planks"),
        part(merge([
            transformed(hard_box(0.052, 0.022, 0.198), (-0.155, 0.006, 0.0)),
            transformed(hard_box(0.052, 0.022, 0.198), (0.155, 0.006, 0.0)),
            transformed(box(0.016, 0.014, 0.205), (-0.155, 0.044, 0.0)),
            transformed(box(0.016, 0.014, 0.205), (0.155, 0.044, 0.0)),
            transformed(box(0.90, 0.018, 0.018), (0.0, 0.044, -0.112)),
            transformed(box(0.90, 0.018, 0.018), (0.0, 0.044, 0.112)),
        ]), [0.14, 0.075, 0.035, 1.0], "boardwalk_segment_gaps_and_edges"),
        part(merge(worn_edges), [0.64, 0.43, 0.22, 1.0], "boardwalk_segment_worn_edges"),
        part(merge(nail_heads), [0.09, 0.055, 0.030, 1.0], "boardwalk_segment_nail_heads"),
    ]


def culvert_pipe_parts():
    return [
        part(pipe(0.325, 1.2, 24), [0.35, 0.36, 0.35, 1.0], "culvert_pipe_body"),
        part(merge([
            transformed(pipe(0.34, 0.08, 24), (0.0, 0.0, -0.56)),
            transformed(pipe(0.34, 0.08, 24), (0.0, 0.0, 0.56)),
        ]), [0.20, 0.21, 0.20, 1.0], "culvert_pipe_rims"),
        part(merge([
            transformed(pipe(0.255, 0.035, 20), (0.0, 0.0, -0.605)),
            transformed(pipe(0.255, 0.035, 20), (0.0, 0.0, 0.605)),
        ]), [0.050, 0.055, 0.052, 1.0], "culvert_pipe_dark_openings"),
        part(merge([
            transformed(hard_box(0.42, 0.035, 0.045), (0.0, 0.63, -0.35), rotation=(0.0, 0.0, 0.12)),
            transformed(hard_box(0.36, 0.030, 0.040), (0.0, 0.61, 0.28), rotation=(0.0, 0.0, -0.10)),
        ]), [0.52, 0.49, 0.42, 1.0], "culvert_pipe_worn_highlights"),
    ]


def log_ramp_parts():
    bark_strips = []
    for x_offset in [-0.14, 0.0, 0.14]:
        bark_strips.append(transformed(box(0.030, 0.022, 0.92), (x_offset, 0.205, 0.03), rotation=(0.0, float(x_offset) * 1.6, 0.0)))
    return [
        part(wedge(0.42, 0.20, 1.15), [0.33, 0.19, 0.09, 1.0], "log_ramp_body"),
        part(transformed(wedge(0.30, 0.025, 0.95), (0.0, 0.195, 0.02)), [0.58, 0.38, 0.18, 1.0], "log_ramp_worn_top"),
        part(merge(bark_strips), [0.18, 0.10, 0.045, 1.0], "log_ramp_bark_strips"),
        part(merge([
            transformed(hard_capped_cylinder(0.055, 0.020, 12), (-0.17, 0.050, -0.48), rotation=(math.pi * 0.5, 0.0, 0.0)),
            transformed(hard_capped_cylinder(0.048, 0.020, 12), (0.17, 0.150, 0.48), rotation=(math.pi * 0.5, 0.0, 0.0)),
        ]), [0.66, 0.45, 0.24, 1.0], "log_ramp_cut_ends"),
    ]


def stepping_stone_parts():
    edge_chips = []
    for index, angle in enumerate([0.2, 1.35, 2.45, 3.70, 5.10]):
        edge_chips.append(transformed(
            box(0.070, 0.014, 0.038),
            (math.cos(angle) * 0.185, 0.073, math.sin(angle) * 0.185),
            rotation=(0.0, -angle, 0.0),
        ))
    return [
        part(cylinder(0.24, 0.068, 16), [0.34, 0.36, 0.34, 1.0], "stepping_stone_base"),
        part(transformed(cylinder(0.21, 0.012, 16), (0.0, 0.068, 0.0)), [0.50, 0.54, 0.52, 1.0], "stepping_stone_wet_top"),
        part(merge(edge_chips), [0.22, 0.25, 0.23, 1.0], "stepping_stone_edge_chips"),
        part(merge([
            transformed(box(0.17, 0.006, 0.020), (-0.04, 0.083, -0.04), rotation=(0.0, 0.42, 0.0)),
            transformed(box(0.11, 0.006, 0.018), (0.06, 0.084, 0.07), rotation=(0.0, -0.72, 0.0)),
        ]), [0.76, 0.86, 0.86, 1.0], "stepping_stone_wet_glints"),
    ]


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    assets = [
        ("boardwalk_segment", "wood_plank", boardwalk_segment_parts()),
        ("culvert_pipe", "packed_dirt", culvert_pipe_parts()),
        ("log_ramp", "wood_plank", log_ramp_parts()),
        ("stepping_stone", "wet_stone", stepping_stone_parts()),
    ]
    for asset_name, surface_id, parts in assets:
        output_path = out_dir / (asset_name + ".glb")
        write_glb_parts(output_path, asset_name, parts, generator=GENERATOR_NAME, roughness_factor=ROUGHNESS_FACTOR, surface_id=surface_id)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
