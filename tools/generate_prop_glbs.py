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


def tapered_cylinder(bottom_radius, top_radius, height, segments, wobble):
    vertices = []
    for ring_index, y in enumerate((0.0, height)):
        ring_radius = bottom_radius if ring_index == 0 else top_radius
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            ripple = 1.0 + math.sin(angle * 3.0 + float(ring_index) * 0.6) * wobble
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
        out.append((
            x + offset[0],
            y + offset[1],
            z + offset[2],
        ))
    return out, indices


def radial_box(width, height, depth, radius, y_offset, angle):
    return transformed(
        box(width, height, depth),
        (math.cos(angle) * radius, y_offset, math.sin(angle) * radius),
        rotation=(0.0, math.pi * 0.5 - angle, 0.0),
    )


def radial_cylinder(radius, length, start_radius, y_offset, angle, scale=(1.0, 1.0, 1.0)):
    return transformed(
        cylinder(radius, length, 10, 0.08),
        (math.cos(angle) * start_radius, y_offset, math.sin(angle) * start_radius),
        scale=scale,
        rotation=(0.0, -angle, -math.pi * 0.5),
    )


def merge(meshes):
    vertices = []
    indices = []
    for mesh_vertices, mesh_indices in meshes:
        base_index = len(vertices)
        vertices.extend(mesh_vertices)
        for index in mesh_indices:
            indices.append(index + base_index)
    return vertices, indices


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
    map_pins = []
    for x_offset, y_offset in [(-0.33, 0.75), (0.22, 0.66), (0.34, 0.45)]:
        map_pins.append(transformed(box(0.035, 0.035, 0.014), (x_offset, y_offset, -0.046)))
    return [
        part(merge([
            transformed(box(0.08, 1.22, 0.08), (-0.46, 0.0, 0.0)),
            transformed(box(0.08, 1.22, 0.08), (0.46, 0.0, 0.0)),
        ]), [0.26, 0.16, 0.08, 1.0], "kiosk_posts"),
        part(merge([
            transformed(box(0.98, 0.58, 0.07), (0.0, 0.52, 0.0)),
            transformed(box(0.86, 0.09, 0.06), (0.0, 0.20, -0.01)),
        ]), [0.45, 0.30, 0.16, 1.0], "kiosk_panel_shelf"),
        part(merge([
            transformed(box(1.18, 0.08, 0.30), (0.0, 1.12, 0.0)),
            transformed(box(1.02, 0.045, 0.045), (0.0, 1.075, -0.145)),
            transformed(box(1.02, 0.045, 0.045), (0.0, 1.075, 0.145)),
        ]), [0.18, 0.12, 0.07, 1.0], "kiosk_roof_trim"),
        part(merge([
            transformed(box(0.30, 0.18, 0.012), (-0.25, 0.66, -0.042)),
            transformed(box(0.22, 0.13, 0.012), (0.24, 0.61, -0.043)),
            transformed(box(0.38, 0.055, 0.012), (0.03, 0.42, -0.044)),
        ]), [0.72, 0.66, 0.48, 1.0], "kiosk_map_cards"),
        part(merge(map_pins), [0.62, 0.16, 0.10, 1.0], "kiosk_map_pins"),
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
    ridges = []
    for index in range(16):
        angle = math.tau * float(index) / 16.0
        ridges.append(transformed(
            box(0.017, 0.022, 0.030),
            (math.cos(angle) * 0.074, 0.029, math.sin(angle) * 0.074),
            rotation=(0.0, -angle, 0.0),
        ))
    return [
        part(cylinder(0.075, 0.035, 20, 0.035), [0.56, 0.10, 0.08, 1.0], "bottle_cap_shell"),
        part(merge(ridges), [0.78, 0.68, 0.50, 1.0], "bottle_cap_ridges"),
        part(transformed(cylinder(0.052, 0.006, 16, 0.01), (0.0, 0.035, 0.0)), [0.86, 0.72, 0.46, 1.0], "bottle_cap_worn_top"),
    ]


def picnic_table_parts():
    top_planks = []
    for z_offset in [-0.15, 0.0, 0.15]:
        top_planks.append(transformed(box(1.25, 0.055, 0.115), (0.0, 0.54, z_offset)))
    bench_planks = []
    for z_offset in [-0.47, -0.36, 0.36, 0.47]:
        bench_planks.append(transformed(box(1.12, 0.055, 0.08), (0.0, 0.33, z_offset)))
    nail_heads = []
    for x_offset in [-0.52, 0.52]:
        for z_offset in [-0.15, 0.0, 0.15, -0.47, -0.36, 0.36, 0.47]:
            y_offset = 0.598 if abs(z_offset) < 0.2 else 0.388
            nail_heads.append(transformed(box(0.028, 0.008, 0.018), (x_offset, y_offset, z_offset)))
    return [
        part(merge(top_planks + bench_planks), [0.48, 0.30, 0.16, 1.0], "picnic_table_planks"),
        part(merge([
            transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, -0.16)),
            transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, -0.16)),
            transformed(box(0.08, 0.52, 0.08), (-0.45, 0.0, 0.16)),
            transformed(box(0.08, 0.52, 0.08), (0.45, 0.0, 0.16)),
            transformed(box(1.05, 0.045, 0.055), (0.0, 0.45, 0.0)),
            transformed(box(0.07, 0.045, 0.92), (-0.45, 0.28, 0.0)),
            transformed(box(0.07, 0.045, 0.92), (0.45, 0.28, 0.0)),
        ]), [0.25, 0.16, 0.08, 1.0], "picnic_table_legs"),
        part(merge(nail_heads), [0.16, 0.10, 0.06, 1.0], "picnic_table_nail_heads"),
    ]


def old_cedar_outer_shell():
    segment_count = 28
    front_angle = math.pi * 0.5
    front_gap = 0.35
    ring_data = [
        (0.18, 0.61),
        (0.43, 0.54),
        (0.76, 0.45),
        (1.0, 0.36),
    ]
    vertices = []
    active_segments = []
    top_heights = []
    for segment in range(segment_count):
        angle = math.tau * float(segment) / float(segment_count)
        front_delta = abs(math.atan2(math.sin(angle - front_angle), math.cos(angle - front_angle)))
        active_segments.append(front_delta > front_gap)
        top_heights.append(
            0.98
            + math.sin(float(segment) * 1.37) * 0.105
            + math.sin(float(segment) * 2.71) * 0.045
        )
    for ring_index, ring in enumerate(ring_data):
        ring_y, ring_radius = ring
        for segment in range(segment_count):
            angle = math.tau * float(segment) / float(segment_count)
            wobble = 1.0 + math.sin(angle * 3.0) * 0.055 + math.sin(angle * 7.0 + 0.4) * 0.025
            y = top_heights[segment] if ring_index == len(ring_data) - 1 else ring_y
            radius = ring_radius * wobble
            vertices.append((math.cos(angle) * radius * 1.08, y, math.sin(angle) * radius * 0.96))
    indices = []
    for ring_index in range(len(ring_data) - 1):
        for segment in range(segment_count):
            next_segment = (segment + 1) % segment_count
            if not active_segments[segment] or not active_segments[next_segment]:
                continue
            bottom_a = ring_index * segment_count + segment
            bottom_b = ring_index * segment_count + next_segment
            top_a = (ring_index + 1) * segment_count + segment
            top_b = (ring_index + 1) * segment_count + next_segment
            indices.extend([bottom_a, bottom_b, top_b, bottom_a, top_b, top_a])
    return vertices, indices


def splinter_prism(width, height, depth, tip_offset):
    half_width = width * 0.5
    half_depth = depth * 0.5
    vertices = [
        (-half_width, 0.0, -half_depth),
        (half_width, 0.0, -half_depth),
        (half_width, 0.0, half_depth),
        (-half_width, 0.0, half_depth),
        (tip_offset, height, -half_depth),
        (tip_offset, height, half_depth),
    ]
    indices = [
        0, 3, 2, 0, 2, 1,
        0, 1, 4,
        3, 5, 2,
        0, 4, 5, 0, 5, 3,
        1, 2, 5, 1, 5, 4,
    ]
    return vertices, indices


def old_cedar_stump_parts():
    shell_panels = []
    bark_highlights = []
    charred_interior = []
    rim_chunks = []
    panel_count = 28
    front_angle = math.pi * 0.5
    shell_panels.append(old_cedar_outer_shell())
    for index in range(panel_count):
        angle = math.tau * float(index) / float(panel_count)
        front_delta = abs(math.atan2(math.sin(angle - front_angle), math.cos(angle - front_angle)))
        panel_height = 0.96 + math.sin(float(index) * 1.37) * 0.105 + math.sin(float(index) * 2.71) * 0.045
        if front_delta < 0.36:
            if index % 2 == 0:
                charred_interior.append(radial_box(0.050, 0.68, 0.024, 0.300, 0.18, angle))
            continue
        if index % 2 == 0:
            bark_highlights.append(radial_box(0.035, 0.42 + float(index % 4) * 0.075, 0.022, 0.525, 0.20, angle + 0.018))
        if index % 3 == 0:
            rim_chunks.append(radial_box(0.145, 0.050 + float(index % 2) * 0.030, 0.090, 0.405, panel_height - 0.015, angle))
    broad_base = transformed(tapered_cylinder(0.70, 0.54, 0.30, 28, 0.075), (0.0, 0.0, 0.0), scale=(1.08, 1.0, 0.96))
    roots = []
    for index, angle in enumerate([-2.85, -2.15, -1.35, -0.48, 0.28, 1.05, 2.25, 2.85]):
        root_length = 0.38 + float(index % 3) * 0.055
        roots.append(radial_cylinder(0.055 + float(index % 2) * 0.010, root_length, 0.46, 0.076, angle, (1.0, 0.82, 1.0)))
        if index % 2 == 0:
            roots.append(radial_box(0.24, 0.17, 0.10, 0.43, 0.015, angle + 0.06))
    broken_splinters = [
        transformed(splinter_prism(0.090, 0.42, 0.045, -0.020), (-0.28, 0.88, 0.31), rotation=(0.10, 0.62, 0.22)),
        transformed(splinter_prism(0.072, 0.50, 0.040, 0.018), (0.17, 0.82, 0.36), rotation=(-0.08, -0.34, -0.18)),
        transformed(splinter_prism(0.066, 0.36, 0.034, -0.016), (0.35, 0.84, -0.02), rotation=(0.02, -1.52, -0.15)),
        transformed(splinter_prism(0.078, 0.32, 0.038, 0.024), (-0.38, 0.80, -0.11), rotation=(0.04, 1.92, 0.18)),
        transformed(splinter_prism(0.060, 0.44, 0.032, -0.010), (0.03, 0.90, -0.36), rotation=(-0.08, 3.03, 0.12)),
        transformed(splinter_prism(0.050, 0.28, 0.030, 0.012), (-0.05, 0.96, 0.39), rotation=(0.08, 0.04, -0.10)),
    ]
    branch_stubs = [
        radial_cylinder(0.060, 0.32, 0.50, 0.56, 0.16, (1.0, 0.86, 1.0)),
        radial_cylinder(0.048, 0.27, 0.46, 0.45, 3.55, (1.0, 0.80, 1.0)),
        radial_box(0.22, 0.036, 0.082, 0.43, 0.82, 5.18),
    ]
    return [
        part(broad_base, [0.27, 0.145, 0.070, 1.0], "old_cedar_stump_broad_base"),
        part(merge(shell_panels), [0.35, 0.20, 0.10, 1.0], "old_cedar_stump_bark_shell"),
        part(merge(roots), [0.20, 0.115, 0.055, 1.0], "old_cedar_stump_root_flares"),
        part(merge(rim_chunks), [0.57, 0.38, 0.19, 1.0], "old_cedar_stump_broken_rim"),
        part(merge(charred_interior + [
            transformed(box(0.56, 0.72, 0.034), (0.0, 0.20, 0.225)),
            transformed(box(0.36, 0.44, 0.026), (0.0, 0.32, -0.19)),
        ]), [0.060, 0.038, 0.024, 1.0], "old_cedar_stump_hollow_shadow"),
        part(merge(branch_stubs), [0.22, 0.13, 0.07, 1.0], "old_cedar_stump_branch_scars"),
        part(merge(bark_highlights + broken_splinters), [0.14, 0.078, 0.036, 1.0], "old_cedar_stump_bark_splits"),
        part(merge([
            radial_box(0.21, 0.034, 0.062, 0.31, 0.94, 3.85),
            radial_box(0.14, 0.028, 0.052, 0.28, 1.02, 4.42),
            radial_box(0.18, 0.028, 0.056, 0.30, 0.98, 5.08),
            radial_box(0.12, 0.026, 0.046, 0.24, 1.06, 5.65),
        ]), [0.68, 0.49, 0.25, 1.0], "old_cedar_stump_inner_cut_edges"),
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
    logs = [
        transformed(cylinder(0.035, 0.52, 10, 0.05), (0.0, 0.045, 0.0), rotation=(0.0, 0.45, math.pi * 0.5)),
        transformed(cylinder(0.032, 0.48, 10, 0.05), (0.0, 0.07, 0.0), rotation=(0.0, -0.55, math.pi * 0.5)),
    ]
    return [
        part(merge(stones), [0.34, 0.33, 0.29, 1.0], "fire_ring_stones"),
        part(transformed(cylinder(0.24, 0.015, 14, 0.02), (0.0, 0.0, 0.0)), [0.12, 0.11, 0.10, 1.0], "fire_ring_ash"),
        part(merge(logs), [0.20, 0.11, 0.05, 1.0], "fire_ring_charred_logs"),
        part(transformed(cylinder(0.07, 0.01, 10, 0.03), (0.0, 0.082, 0.0)), [0.85, 0.27, 0.08, 1.0], "fire_ring_embers"),
    ]


def hiking_boot_parts():
    laces = []
    for index, x_offset in enumerate([-0.11, -0.04, 0.03, 0.10]):
        angle = -0.42 if index % 2 == 0 else 0.42
        laces.append(transformed(box(0.12, 0.012, 0.014), (x_offset, 0.245, 0.0), rotation=(0.0, angle, 0.0)))
    treads = []
    for x_offset in [-0.18, -0.05, 0.08, 0.21]:
        treads.append(transformed(box(0.055, 0.018, 0.205), (x_offset, 0.0, 0.0)))
    return [
        part(merge([
            transformed(box(0.46, 0.08, 0.18), (0.0, 0.0, 0.0)),
            transformed(box(0.18, 0.08, 0.16), (0.2, 0.08, 0.0)),
        ]), [0.07, 0.05, 0.035, 1.0], "hiking_boot_sole_toe"),
        part(merge([
            transformed(box(0.34, 0.18, 0.17), (-0.03, 0.06, 0.0)),
            transformed(box(0.15, 0.24, 0.16), (-0.2, 0.16, 0.0)),
        ]), [0.28, 0.16, 0.08, 1.0], "hiking_boot_upper"),
        part(merge(laces), [0.78, 0.67, 0.50, 1.0], "hiking_boot_laces"),
        part(merge(treads), [0.035, 0.030, 0.025, 1.0], "hiking_boot_treads"),
    ]


def water_bottle_parts():
    return [
        part(transformed(cylinder(0.08, 0.42, 16, 0.02), (0.0, 0.0, 0.0)), [0.16, 0.42, 0.58, 1.0], "water_bottle_body"),
        part(transformed(cylinder(0.081, 0.105, 16, 0.01), (0.0, 0.17, 0.0)), [0.82, 0.88, 0.80, 1.0], "water_bottle_label"),
        part(transformed(box(0.022, 0.34, 0.010), (0.058, 0.06, -0.058), rotation=(0.0, -0.78, 0.0)), [0.74, 0.91, 0.96, 1.0], "water_bottle_highlight"),
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
