#!/usr/bin/env python3
import argparse
import json
import math
import struct
from pathlib import Path

from simple_glb_writer import (
    compute_normals,
    compute_uvs,
    pack_normals,
    pack_uvs,
    vector_cross,
    vector_dot,
    vector_normalized,
    vector_sub,
)

OUT_DIR = Path("assets/models/vehicle")

# --- FIDELITY (buggy-hero) palette + PBR -------------------------------------
# Hero direction: the buggy is the most-looked-at object, so it must read as a
# crisp manufactured machine that POPS against warm red-rock Zion -- not blend
# into it. The world palette is dominated by red-orange / salmon / apricot
# sandstone (zion-art-direction-bible.md), so the prior red-orange body
# (0.93,0.18,0.07) camouflaged. The hero now wears a deep desert PETROL-TEAL --
# the complement of the rock -- with warm CREAM number plates and a SAFETY-AMBER
# hazard accent (ties to the kayak topper + headlight warmth). Two-tone teal +
# amber over a matte-black anodized cage = believable hobby-grade RC livery that
# stays legible from the chase cam and at orbit distance.
#
# Colors are LINEAR-RGB (Godot Color()/glTF baseColorFactor in Forward+ HDR are
# linear), authored to sit clearly off the rock hue. PBR factors give each part
# a real metallic/roughness response instead of the old uniform flat plastic
# (metal 0.0 / rough 0.82). Runtime polish in procedural_buggy_visual.gd
# (clearcoat, rim cap, cage metalness) layers on top; these base values make the
# object correct-by-construction even before that runs.
#
# Render-only: NOTHING here touches mesh geometry the sim reads. The wheel_tire
# mesh args (treaded_tire(0.031,0.034,...)) are LOCKED by D41 (rolling radius
# 0.03765) and left untouched -- only its material/color changes. Wheel-socket
# node translations + the rc_buggy/wheel_mesh hierarchy are the SIM contract
# (tools/check_glb.py) and are likewise untouched.
HERO_BODY_TEAL = [0.045, 0.205, 0.215, 1.0]        # deep petrol-teal hero paint
HERO_BODY_TEAL_DEEP = [0.030, 0.150, 0.165, 1.0]   # shadowed side pods (darker teal)
HERO_AMBER = [0.86, 0.30, 0.045, 1.0]              # safety-amber hazard accent
HERO_AMBER_DEEP = [0.74, 0.235, 0.035, 1.0]        # amber fender flares (a touch deeper)
HERO_CREAM = [0.90, 0.84, 0.70, 1.0]               # cream number plates / livery stripe
HERO_CANOPY = [0.20, 0.40, 0.45, 0.55]             # smoked teal-tint canopy (translucent)
ANODIZE_BLACK = [0.045, 0.050, 0.058, 1.0]         # matte-black anodized cage / wing / bumper
GRAPHITE = [0.028, 0.030, 0.034, 1.0]              # dark composite suspension arms / vents
RUBBER_BLACK = [0.022, 0.022, 0.025, 1.0]          # tire rubber (near-black, faint sheen)
RIM_ALU = [0.30, 0.31, 0.33, 1.0]                  # brushed-aluminum rim
HUB_MACHINED = [0.55, 0.52, 0.46, 1.0]             # machined warm-metal hub cap
SKID_ALU = [0.20, 0.21, 0.225, 1.0]                # scuffed alloy skid plate
SHOCK_AMBER = [0.78, 0.40, 0.12, 1.0]              # anodized amber shock spring (matches accent)
HEADLIGHT_LENS = [1.00, 0.86, 0.46, 1.0]           # warm amber headlight lens
TAILLIGHT_LENS = [0.95, 0.05, 0.025, 1.0]          # red tail-light lens

# Per-material PBR response (roughness, metallic). Painted shells stay dielectric
# with a faint flake; metal parts go metallic with lower roughness so sun reads
# as a defined highlight instead of a flat wash.
PBR_PAINT = (0.36, 0.10)        # automotive paint: glossy-ish, faint metallic flake
PBR_PAINT_AMBER = (0.40, 0.08)  # accent paint: slightly more matte
PBR_CREAM = (0.55, 0.0)         # cream decal/plate: matte dielectric
PBR_CANOPY = (0.12, 0.0)        # smoked canopy: glossy clear
PBR_ANODIZE = (0.34, 0.85)      # anodized cage tubing: metallic, semi-gloss
PBR_GRAPHITE = (0.62, 0.20)     # composite arms/vents: matte, faint metal
PBR_RUBBER = (0.88, 0.0)        # tire rubber: rough dielectric
PBR_RIM = (0.30, 0.92)          # brushed aluminum: bright metal, micro-roughness
PBR_HUB = (0.34, 0.88)          # machined hub: metal
PBR_SKID = (0.42, 0.78)         # scuffed alloy skid plate: metal, rougher (wear)
PBR_SHOCK = (0.30, 0.65)        # anodized spring: semi-metal
PBR_LENS = (0.18, 0.0)          # glossy clear lens
PBR_DARK_TRIM = (0.55, 0.15)    # grille / fender-lip / number-mark dark trim


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead vehicle GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated vehicle GLBs.")
    return parser.parse_args()


def pad4(data, pad_byte=b" "):
    padding = (-len(data)) % 4
    if padding:
        data += pad_byte * padding
    return data


def append_aligned(buffer, chunk, alignment=4):
    padding = (-len(buffer)) % alignment
    if padding:
        buffer.extend(b"\0" * padding)
    offset = len(buffer)
    buffer.extend(chunk)
    return offset


def pack_positions(vertices):
    return b"".join(struct.pack("<fff", vertex[0], vertex[1], vertex[2]) for vertex in vertices)


def pack_indices(indices):
    return b"".join(struct.pack("<H", index) for index in indices)


def bounds(vertices):
    mins = [min(vertex[index] for vertex in vertices) for index in range(3)]
    maxs = [max(vertex[index] for vertex in vertices) for index in range(3)]
    return mins, maxs


def box(width, height, depth):
    x = width * 0.5
    y = height * 0.5
    z = depth * 0.5
    vertices = [
        (-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
        (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z),
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


def oriented_box(center, axis_a, length_a, axis_b, length_b, axis_c, length_c):
    half_a = length_a * 0.5
    half_b = length_b * 0.5
    half_c = length_c * 0.5
    vertices = []
    for sign_a, sign_b, sign_c in (
        (-1.0, -1.0, -1.0), (1.0, -1.0, -1.0), (1.0, 1.0, -1.0), (-1.0, 1.0, -1.0),
        (-1.0, -1.0, 1.0), (1.0, -1.0, 1.0), (1.0, 1.0, 1.0), (-1.0, 1.0, 1.0),
    ):
        vertices.append((
            center[0] + axis_a[0] * half_a * sign_a + axis_b[0] * half_b * sign_b + axis_c[0] * half_c * sign_c,
            center[1] + axis_a[1] * half_a * sign_a + axis_b[1] * half_b * sign_b + axis_c[1] * half_c * sign_c,
            center[2] + axis_a[2] * half_a * sign_a + axis_b[2] * half_b * sign_b + axis_c[2] * half_c * sign_c,
        ))
    indices = [
        0, 1, 2, 0, 2, 3,
        4, 6, 5, 4, 7, 6,
        0, 4, 5, 0, 5, 1,
        3, 2, 6, 3, 6, 7,
        1, 5, 6, 1, 6, 2,
        0, 3, 7, 0, 7, 4,
    ]
    return vertices, indices


def vector_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vector_scale(value, scale):
    return (value[0] * scale, value[1] * scale, value[2] * scale)


def vector_length(value):
    return math.sqrt(vector_dot(value, value))


def midpoint(a, b):
    return (
        (a[0] + b[0]) * 0.5,
        (a[1] + b[1]) * 0.5,
        (a[2] + b[2]) * 0.5,
    )


def perpendicular_basis(axis):
    reference = (0.0, 1.0, 0.0)
    if abs(vector_dot(axis, reference)) > 0.88:
        reference = (1.0, 0.0, 0.0)
    basis_a = vector_normalized(vector_cross(axis, reference), (1.0, 0.0, 0.0))
    basis_b = vector_normalized(vector_cross(axis, basis_a), (0.0, 0.0, 1.0))
    return basis_a, basis_b


def cylinder_between(start, end, radius, segments, capped=True):
    axis = vector_sub(end, start)
    if vector_length(axis) <= 0.000001:
        return [], []
    axis = vector_normalized(axis)
    basis_a, basis_b = perpendicular_basis(axis)
    vertices = []
    for center in (start, end):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            radial = vector_add(
                vector_scale(basis_a, math.cos(angle) * radius),
                vector_scale(basis_b, math.sin(angle) * radius),
            )
            vertices.append(vector_add(center, radial))
    indices = []
    for segment in range(segments):
        next_segment = (segment + 1) % segments
        bottom_a = segment
        bottom_b = next_segment
        top_a = segment + segments
        top_b = next_segment + segments
        indices.extend([bottom_a, bottom_b, top_b, bottom_a, top_b, top_a])
    if capped:
        bottom_center = len(vertices)
        top_center = len(vertices) + 1
        vertices.append(start)
        vertices.append(end)
        for segment in range(segments):
            next_segment = (segment + 1) % segments
            indices.extend([bottom_center, next_segment, segment])
            indices.extend([top_center, segment + segments, next_segment + segments])
    return vertices, indices


def rod_box_between(start, end, width, thickness):
    axis = vector_sub(end, start)
    length = vector_length(axis)
    if length <= 0.000001:
        return [], []
    axis = vector_normalized(axis)
    up_axis = (0.0, 1.0, 0.0)
    side_axis = vector_normalized(vector_cross(axis, up_axis), (0.0, 0.0, 1.0))
    return oriented_box(midpoint(start, end), axis, length, up_axis, thickness, side_axis, width)


def joint_ball(center, radius):
    x = (radius, 0.0, 0.0)
    y = (0.0, radius, 0.0)
    z = (0.0, 0.0, radius)
    vertices = [
        vector_add(center, y),
        vector_add(center, vector_scale(y, -1.0)),
        vector_add(center, x),
        vector_add(center, vector_scale(x, -1.0)),
        vector_add(center, z),
        vector_add(center, vector_scale(z, -1.0)),
    ]
    indices = [
        0, 2, 4,
        0, 4, 3,
        0, 3, 5,
        0, 5, 2,
        1, 4, 2,
        1, 3, 4,
        1, 5, 3,
        1, 2, 5,
    ]
    return vertices, indices


def triangular_plate(points, normal, thickness):
    offset = vector_scale(vector_normalized(normal), thickness * 0.5)
    vertices = [
        vector_add(points[0], vector_scale(offset, -1.0)),
        vector_add(points[1], vector_scale(offset, -1.0)),
        vector_add(points[2], vector_scale(offset, -1.0)),
        vector_add(points[0], offset),
        vector_add(points[1], offset),
        vector_add(points[2], offset),
    ]
    indices = [
        0, 1, 2,
        3, 5, 4,
        0, 3, 4, 0, 4, 1,
        1, 4, 5, 1, 5, 2,
        2, 5, 3, 2, 3, 0,
    ]
    return vertices, indices


def wedge(width, height, depth):
    x = width * 0.5
    y = height * 0.5
    z = depth * 0.5
    vertices = [
        (-x, -y, -z), (x, -y, -z), (-x, y, z), (x, y, z),
        (-x, -y, z), (x, -y, z),
    ]
    indices = [
        0, 1, 3, 0, 3, 2,
        4, 2, 3, 4, 3, 5,
        0, 4, 5, 0, 5, 1,
        0, 2, 4,
        1, 5, 3,
    ]
    return vertices, indices


def combine_meshes(meshes):
    vertices = []
    indices = []
    for mesh_vertices, mesh_indices in meshes:
        offset = len(vertices)
        vertices.extend(mesh_vertices)
        indices.extend(index + offset for index in mesh_indices)
    return vertices, indices


def translated(mesh, offset):
    vertices, indices = mesh
    return [
        (vertex[0] + offset[0], vertex[1] + offset[1], vertex[2] + offset[2])
        for vertex in vertices
    ], indices


def cylinder_y(radius, height, segments):
    vertices = []
    y_min = -height * 0.5
    y_max = height * 0.5
    for y in (y_min, y_max):
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            vertices.append((math.cos(angle) * radius, y, math.sin(angle) * radius))
    vertices.append((0.0, y_min, 0.0))
    vertices.append((0.0, y_max, 0.0))
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


def coil_spring_y(radius, wire_radius, height, turns, segments_per_turn, ring_segments):
    meshes = []
    steps = int(turns * float(segments_per_turn))
    previous = None
    for step in range(steps + 1):
        t = float(step) / float(steps)
        angle = math.tau * turns * t
        point = (
            math.cos(angle) * radius,
            -height * 0.5 + height * t,
            math.sin(angle) * radius,
        )
        if previous is not None:
            meshes.append(cylinder_between(previous, point, wire_radius, ring_segments, False))
        previous = point
    return combine_meshes(meshes)


def tread_block(angle, radius, width, radial_depth, tangential_width):
    radial = (math.cos(angle), 0.0, math.sin(angle))
    tangent = (-math.sin(angle), 0.0, math.cos(angle))
    y_axis = (0.0, 1.0, 0.0)
    center = (radial[0] * (radius + radial_depth * 0.45), 0.0, radial[2] * (radius + radial_depth * 0.45))
    return oriented_box(center, radial, radial_depth, y_axis, width, tangent, tangential_width)


def treaded_tire(radius, width, segments, tread_count):
    meshes = [cylinder_y(radius, width, segments)]
    for tread_index in range(tread_count):
        angle = math.tau * float(tread_index) / float(tread_count)
        meshes.append(tread_block(angle, radius, width * 0.88, 0.007, 0.010))
    return combine_meshes(meshes)


def buggy_body_shell():
    sections = [
        (-0.118, 0.044, 0.030, -0.026, 0.000),
        (-0.040, 0.074, 0.058, -0.026, 0.035),
        (0.060, 0.074, 0.060, -0.024, 0.030),
        (0.124, 0.056, 0.046, -0.020, 0.010),
    ]
    vertices = []
    for z, lower_width, upper_width, low_y, high_y in sections:
        vertices.extend([
            (-lower_width, low_y, z),
            (lower_width, low_y, z),
            (-upper_width, high_y, z),
            (upper_width, high_y, z),
        ])
    indices = []
    for section_index in range(len(sections) - 1):
        a = section_index * 4
        b = (section_index + 1) * 4
        indices.extend([a, b, b + 1, a, b + 1, a + 1])
        indices.extend([a + 2, a + 3, b + 3, a + 2, b + 3, b + 2])
        indices.extend([a, a + 2, b + 2, a, b + 2, b])
        indices.extend([a + 1, b + 1, b + 3, a + 1, b + 3, a + 3])
    last = (len(sections) - 1) * 4
    indices.extend([0, 1, 3, 0, 3, 2])
    indices.extend([last, last + 2, last + 3, last, last + 3, last + 1])
    return vertices, indices


def fender_flare_mesh():
    meshes = []
    for x_sign in (-1.0, 1.0):
        for z_center in (-0.100, 0.100):
            meshes.append(oriented_box(
                (0.085 * x_sign, 0.025, z_center),
                (1.0, 0.0, 0.0),
                0.052,
                (0.0, 1.0, 0.0),
                0.014,
                (0.0, 0.0, 1.0),
                0.074,
            ))
    return combine_meshes(meshes)


def fender_lip_mesh():
    meshes = []
    for x_sign in (-1.0, 1.0):
        for z_center in (-0.100, 0.100):
            meshes.append(translated(box(0.010, 0.018, 0.078), (0.113 * x_sign, 0.020, z_center)))
            meshes.append(translated(box(0.050, 0.013, 0.010), (0.088 * x_sign, 0.020, z_center - 0.041)))
            meshes.append(translated(box(0.050, 0.013, 0.010), (0.088 * x_sign, 0.020, z_center + 0.041)))
    return combine_meshes(meshes)


def headlight_mesh():
    meshes = []
    for x_offset in (-0.038, 0.038):
        meshes.append(cylinder_between(
            (x_offset, 0.030, -0.211),
            (x_offset, 0.030, -0.216),
            0.010,
            14,
        ))
    for x_offset in (-0.024, 0.024):
        meshes.append(cylinder_between(
            (x_offset, 0.123, -0.112),
            (x_offset, 0.123, -0.118),
            0.008,
            12,
        ))
    return combine_meshes(meshes)


def tail_light_mesh():
    return combine_meshes([
        translated(box(0.026, 0.012, 0.006), (-0.044, 0.027, 0.171)),
        translated(box(0.026, 0.012, 0.006), (0.044, 0.027, 0.171)),
    ])


def grille_mesh():
    meshes = [
        translated(box(0.076, 0.004, 0.006), (0.0, 0.026, -0.207)),
        translated(box(0.076, 0.004, 0.006), (0.0, 0.018, -0.207)),
        translated(box(0.076, 0.004, 0.006), (0.0, 0.010, -0.207)),
    ]
    for x_offset in (-0.032, 0.0, 0.032):
        meshes.append(translated(box(0.004, 0.020, 0.006), (x_offset, 0.018, -0.206)))
    return combine_meshes(meshes)


def side_number_plate_mesh():
    return combine_meshes([
        translated(box(0.006, 0.030, 0.060), (-0.078, 0.034, -0.006)),
        translated(box(0.006, 0.030, 0.060), (0.078, 0.034, -0.006)),
    ])


def side_number_mark_mesh():
    return combine_meshes([
        translated(box(0.007, 0.004, 0.044), (-0.082, 0.038, -0.006)),
        translated(box(0.007, 0.004, 0.044), (0.082, 0.038, -0.006)),
        translated(box(0.007, 0.004, 0.028), (-0.082, 0.030, -0.006)),
        translated(box(0.007, 0.004, 0.028), (0.082, 0.030, -0.006)),
    ])


def vent_mesh():
    meshes = []
    for x_offset in (-0.040, -0.020, 0.020, 0.040):
        meshes.append(translated(box(0.010, 0.004, 0.052), (x_offset, 0.061, -0.110)))
    for x_offset in (-0.040, -0.020, 0.0, 0.020, 0.040):
        meshes.append(translated(box(0.010, 0.004, 0.046), (x_offset, 0.054, 0.065)))
    for x_sign in (-1.0, 1.0):
        meshes.append(translated(box(0.004, 0.030, 0.154), (0.080 * x_sign, 0.033, 0.010)))
        for z_offset in (-0.070, -0.046, -0.022):
            meshes.append(translated(box(0.005, 0.006, 0.018), (0.084 * x_sign, 0.034, z_offset)))
    meshes.extend([
        translated(box(0.004, 0.004, 0.086), (-0.032, 0.064, -0.080)),
        translated(box(0.004, 0.004, 0.086), (0.032, 0.064, -0.080)),
        translated(box(0.056, 0.004, 0.004), (0.0, 0.064, -0.124)),
        translated(box(0.056, 0.004, 0.004), (0.0, 0.064, -0.036)),
    ])
    return combine_meshes(meshes)


def cage_side_tube_mesh():
    radius = 0.0044
    meshes = [
        cylinder_between((0.0, -0.040, -0.085), (0.0, -0.036, 0.085), radius, 10),
        cylinder_between((0.0, 0.040, -0.078), (0.0, 0.040, 0.078), radius, 10),
        cylinder_between((0.0, -0.040, -0.085), (0.0, 0.040, -0.078), radius, 10),
        cylinder_between((0.0, -0.036, 0.085), (0.0, 0.040, 0.078), radius, 10),
        cylinder_between((0.0, -0.026, -0.040), (0.0, 0.040, 0.020), radius * 0.72, 8),
        cylinder_between((0.0, 0.036, -0.034), (0.0, -0.014, 0.040), radius * 0.72, 8),
    ]
    return combine_meshes(meshes)


def cage_top_tube_mesh():
    radius = 0.0042
    meshes = [
        cylinder_between((-0.060, 0.0, -0.078), (-0.060, 0.0, 0.078), radius, 10),
        cylinder_between((0.060, 0.0, -0.078), (0.060, 0.0, 0.078), radius, 10),
        cylinder_between((-0.060, 0.0, -0.078), (0.060, 0.0, -0.078), radius, 10),
        cylinder_between((-0.060, 0.0, 0.078), (0.060, 0.0, 0.078), radius, 10),
        cylinder_between((-0.052, 0.0, -0.020), (0.052, 0.0, 0.044), radius * 0.70, 8),
        cylinder_between((0.052, 0.0, -0.020), (-0.052, 0.0, 0.044), radius * 0.70, 8),
    ]
    return combine_meshes(meshes)


def cage_crossbar_tube_mesh():
    return cylinder_between((-0.064, 0.0, 0.0), (0.064, 0.0, 0.0), 0.0045, 10)


def bumper_bar_tube_mesh():
    return cylinder_between((-0.083, 0.0, 0.0), (0.083, 0.0, 0.0), 0.0065, 12)


def front_bumper_loop_mesh():
    meshes = [
        cylinder_between((-0.070, -0.020, 0.0), (-0.070, 0.020, 0.0), 0.0048, 10),
        cylinder_between((0.070, -0.020, 0.0), (0.070, 0.020, 0.0), 0.0048, 10),
        cylinder_between((-0.070, 0.020, 0.0), (0.070, 0.020, 0.0), 0.0048, 10),
    ]
    return combine_meshes(meshes)


def detailed_skid_plate_mesh():
    meshes = [
        box(0.118, 0.006, 0.250),
        translated(box(0.012, 0.004, 0.220), (-0.042, 0.005, 0.000)),
        translated(box(0.012, 0.004, 0.220), (0.042, 0.005, 0.000)),
        translated(box(0.050, 0.004, 0.010), (0.0, 0.006, -0.096)),
        translated(box(0.050, 0.004, 0.010), (0.0, 0.006, 0.096)),
    ]
    for x_offset in (-0.038, 0.038):
        for z_offset in (-0.090, 0.090):
            meshes.append(translated(cylinder_y(0.0045, 0.003, 10), (x_offset, 0.007, z_offset)))
    return combine_meshes(meshes)


def roll_cage_detail_mesh():
    meshes = []
    for x_offset in (-0.055, 0.055):
        x_sign = -1.0 if x_offset < 0.0 else 1.0
        joint_points = [
            (x_offset, 0.034, -0.105),
            (x_offset, 0.038, 0.065),
            (x_offset, 0.114, -0.098),
            (x_offset, 0.114, 0.058),
            (x_offset, 0.082, -0.105),
            (x_offset, 0.082, 0.058),
        ]
        for point in joint_points:
            meshes.append(joint_ball(point, 0.0062))
        meshes.append(triangular_plate(
            [
                (x_offset, 0.040, -0.105),
                (x_offset, 0.078, -0.105),
                (x_offset, 0.047, -0.075),
            ],
            (x_sign, 0.0, 0.0),
            0.0025,
        ))
        meshes.append(triangular_plate(
            [
                (x_offset, 0.041, 0.064),
                (x_offset, 0.078, 0.058),
                (x_offset, 0.050, 0.034),
            ],
            (x_sign, 0.0, 0.0),
            0.0025,
        ))
    for x_offset in (-0.038, 0.038):
        meshes.append(cylinder_between(
            (x_offset, 0.030, -0.204),
            (x_offset, 0.030, -0.218),
            0.014,
            14,
        ))
    for x_offset in (-0.024, 0.024):
        meshes.append(cylinder_between(
            (x_offset, 0.123, -0.104),
            (x_offset, 0.123, -0.119),
            0.010,
            12,
        ))
        meshes.append(cylinder_between(
            (x_offset, 0.114, -0.103),
            (x_offset, 0.123, -0.107),
            0.0022,
            8,
        ))
    return combine_meshes(meshes)


def suspension_a_arm_detail_mesh():
    meshes = []
    for x_sign in (-1.0, 1.0):
        for z_center, z_spread in ((-0.100, 0.030), (0.100, 0.030)):
            outer = (0.083 * x_sign, -0.022, z_center)
            inner_front = (0.030 * x_sign, -0.022, z_center - z_spread)
            inner_rear = (0.030 * x_sign, -0.022, z_center + z_spread)
            meshes.append(rod_box_between(inner_front, outer, 0.006, 0.004))
            meshes.append(rod_box_between(inner_rear, outer, 0.006, 0.004))
            upper_outer = (0.074 * x_sign, 0.006, z_center)
            upper_inner = (0.032 * x_sign, 0.014, z_center - z_spread * (1.0 if z_center < 0.0 else -1.0))
            meshes.append(cylinder_between(upper_inner, upper_outer, 0.0024, 8))
            meshes.append(joint_ball(outer, 0.0048))
    return combine_meshes(meshes)


def shock_hardware_mesh():
    meshes = []
    for center in (
        (-0.068, 0.022, -0.096),
        (0.068, 0.022, -0.096),
        (-0.068, 0.024, 0.104),
        (0.068, 0.024, 0.104),
    ):
        meshes.append(translated(cylinder_y(0.0022, 0.066, 10), center))
        meshes.append(translated(cylinder_y(0.0066, 0.004, 12), (center[0], center[1] - 0.031, center[2])))
        meshes.append(translated(cylinder_y(0.0066, 0.004, 12), (center[0], center[1] + 0.031, center[2])))
        meshes.append(joint_ball((center[0], center[1] - 0.036, center[2]), 0.0042))
        meshes.append(joint_ball((center[0], center[1] + 0.036, center[2]), 0.0042))
    return combine_meshes(meshes)


def exhaust_mesh():
    meshes = [
        cylinder_between((0.050, 0.028, 0.060), (0.055, 0.028, 0.100), 0.0030, 8),
        cylinder_between((0.055, 0.028, 0.100), (0.055, 0.028, 0.140), 0.0070, 12),
        cylinder_between((0.055, 0.028, 0.140), (0.072, 0.028, 0.164), 0.0038, 10),
        translated(box(0.017, 0.003, 0.006), (0.055, 0.036, 0.112)),
        translated(box(0.017, 0.003, 0.006), (0.055, 0.036, 0.130)),
    ]
    return combine_meshes(meshes)


def write_glb(path):
    # (name, mesh, baseColorFactor, (roughness, metallic)). FIDELITY hero scheme:
    # teal painted shells, cream/amber livery, anodized cage, real metal running
    # gear. Geometry args are unchanged from the locked layout; only colors + PBR
    # response are tuned (render-only).
    mesh_specs = [
        ("body", buggy_body_shell(), HERO_BODY_TEAL, PBR_PAINT),
        ("nose", wedge(0.115, 0.034, 0.105), HERO_AMBER, PBR_PAINT_AMBER),
        ("top_deck", box(0.105, 0.010, 0.155), GRAPHITE, PBR_GRAPHITE),
        ("side_panel", box(0.006, 0.042, 0.205), HERO_BODY_TEAL_DEEP, PBR_PAINT),
        ("canopy", wedge(0.082, 0.034, 0.088), HERO_CANOPY, PBR_CANOPY),
        ("paint_stripe", box(0.026, 0.004, 0.178), HERO_CREAM, PBR_CREAM),
        ("cage_side", cage_side_tube_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("cage_top", cage_top_tube_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("cage_crossbar", cage_crossbar_tube_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("wing_panel", box(0.178, 0.012, 0.058), ANODIZE_BLACK, PBR_ANODIZE),
        ("wing_stanchion", box(0.012, 0.056, 0.012), ANODIZE_BLACK, PBR_ANODIZE),
        ("bumper_bar", bumper_bar_tube_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("bumper_upright", front_bumper_loop_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("skid_plate", detailed_skid_plate_mesh(), SKID_ALU, PBR_SKID),
        ("shock_coil", coil_spring_y(0.006, 0.0012, 0.058, 4.5, 10, 6), SHOCK_AMBER, PBR_SHOCK),
        ("suspension_arm", box(0.060, 0.004, 0.008), GRAPHITE, PBR_GRAPHITE),
        ("wheel_tire", treaded_tire(0.031, 0.034, 24, 12), RUBBER_BLACK, PBR_RUBBER),
        ("wheel_rim", cylinder_y(0.017, 0.004, 18), RIM_ALU, PBR_RIM),
        ("wheel_hub", cylinder_y(0.008, 0.006, 14), HUB_MACHINED, PBR_HUB),
        ("fender_flare", fender_flare_mesh(), HERO_AMBER_DEEP, PBR_PAINT_AMBER),
        ("fender_lip", fender_lip_mesh(), GRAPHITE, PBR_DARK_TRIM),
        ("headlight_lens", headlight_mesh(), HEADLIGHT_LENS, PBR_LENS),
        ("tail_light_lens", tail_light_mesh(), TAILLIGHT_LENS, PBR_LENS),
        ("front_grille", grille_mesh(), GRAPHITE, PBR_DARK_TRIM),
        ("side_number_plate", side_number_plate_mesh(), HERO_CREAM, PBR_CREAM),
        ("side_number_mark", side_number_mark_mesh(), ANODIZE_BLACK, PBR_DARK_TRIM),
        ("body_vent", vent_mesh(), GRAPHITE, PBR_GRAPHITE),
        ("antenna", cylinder_y(0.0025, 0.118, 8), GRAPHITE, PBR_GRAPHITE),
        ("roll_cage_detail", roll_cage_detail_mesh(), ANODIZE_BLACK, PBR_ANODIZE),
        ("suspension_a_arm_detail", suspension_a_arm_detail_mesh(), GRAPHITE, PBR_GRAPHITE),
        ("shock_hardware", shock_hardware_mesh(), HUB_MACHINED, PBR_HUB),
        ("exhaust", exhaust_mesh(), SKID_ALU, PBR_SKID),
    ]

    binary = bytearray()
    buffer_views = []
    accessors = []
    meshes = []
    materials = []
    for mesh_index, (mesh_name, mesh, color, pbr) in enumerate(mesh_specs):
        roughness_factor, metallic_factor = pbr
        vertices, indices = mesh
        position_data = pack_positions(vertices)
        normal_data = pack_normals(compute_normals(vertices, indices))
        uv_data = pack_uvs(compute_uvs(vertices))
        index_data = pack_indices(indices)
        position_offset = append_aligned(binary, position_data)
        normal_offset = append_aligned(binary, normal_data)
        uv_offset = append_aligned(binary, uv_data)
        index_offset = append_aligned(binary, index_data, 2)
        buffer_views.append({"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962})
        position_accessor = len(accessors)
        mins, maxs = bounds(vertices)
        accessors.append(
            {
                "bufferView": len(buffer_views) - 1,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC3",
                "min": mins,
                "max": maxs,
            }
        )
        buffer_views.append({"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_data), "target": 34962})
        normal_accessor = len(accessors)
        accessors.append(
            {
                "bufferView": len(buffer_views) - 1,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC3",
            }
        )
        buffer_views.append({"buffer": 0, "byteOffset": uv_offset, "byteLength": len(uv_data), "target": 34962})
        uv_accessor = len(accessors)
        accessors.append(
            {
                "bufferView": len(buffer_views) - 1,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC2",
            }
        )
        buffer_views.append({"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963})
        index_accessor = len(accessors)
        accessors.append(
            {
                "bufferView": len(buffer_views) - 1,
                "byteOffset": 0,
                "componentType": 5123,
                "count": len(indices),
                "type": "SCALAR",
                "min": [min(indices)],
                "max": [max(indices)],
            }
        )
        materials.append(
            {
                "name": mesh_name + "_mat",
                "pbrMetallicRoughness": {
                    "baseColorFactor": color,
                    "roughnessFactor": roughness_factor,
                    "metallicFactor": metallic_factor,
                },
            }
        )
        if color[3] < 1.0:
            materials[-1]["alphaMode"] = "BLEND"
        meshes.append(
            {
                "name": mesh_name,
                "primitives": [{
                    "attributes": {
                        "POSITION": position_accessor,
                        "NORMAL": normal_accessor,
                        "TEXCOORD_0": uv_accessor,
                    },
                    "indices": index_accessor,
                    "mode": 4,
                    "material": mesh_index,
                }],
            }
        )

    body_mesh = 0
    nose_mesh = 1
    deck_mesh = 2
    side_panel_mesh = 3
    canopy_mesh = 4
    paint_stripe_mesh = 5
    cage_side_mesh = 6
    cage_top_mesh = 7
    cage_crossbar_mesh = 8
    wing_panel_mesh = 9
    wing_stanchion_mesh = 10
    bumper_bar_mesh = 11
    bumper_upright_mesh = 12
    skid_plate_mesh = 13
    shock_coil_mesh = 14
    suspension_arm_mesh = 15
    tire_mesh = 16
    rim_mesh = 17
    hub_mesh = 18
    fender_flare_mesh_index = 19
    fender_lip_mesh_index = 20
    headlight_mesh_index = 21
    tail_light_mesh_index = 22
    grille_mesh_index = 23
    side_number_plate_mesh_index = 24
    side_number_mark_mesh_index = 25
    vent_mesh_index = 26
    antenna_mesh_index = 27
    roll_cage_detail_mesh_index = 28
    suspension_a_arm_detail_mesh_index = 29
    shock_hardware_mesh_index = 30
    exhaust_mesh_index = 31
    nodes = [
        {"name": "rc_buggy", "children": [1, 2, 3, 4, 5, 6, 7, 13, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 36, 41, 46, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60]},
        {"name": "body", "mesh": body_mesh, "translation": [0.0, 0.010, 0.015]},
        {"name": "nose", "mesh": nose_mesh, "translation": [0.0, 0.018, -0.155]},
        {"name": "top_deck", "mesh": deck_mesh, "translation": [0.0, 0.043, -0.030]},
        {"name": "side_panel_left", "mesh": side_panel_mesh, "translation": [-0.074, 0.008, 0.020]},
        {"name": "side_panel_right", "mesh": side_panel_mesh, "translation": [0.074, 0.008, 0.020]},
        {"name": "canopy", "mesh": canopy_mesh, "translation": [0.0, 0.066, -0.060]},
        {"name": "roll_cage", "children": [8, 9, 10, 11, 12]},
        {"name": "cage_left", "mesh": cage_side_mesh, "translation": [-0.055, 0.074, -0.020]},
        {"name": "cage_right", "mesh": cage_side_mesh, "translation": [0.055, 0.074, -0.020]},
        {"name": "cage_top", "mesh": cage_top_mesh, "translation": [0.0, 0.112, -0.020]},
        {"name": "cage_front", "mesh": cage_crossbar_mesh, "translation": [0.0, 0.082, -0.105]},
        {"name": "cage_rear", "mesh": cage_crossbar_mesh, "translation": [0.0, 0.082, 0.058]},
        {"name": "rear_wing", "children": [14, 15, 16]},
        {"name": "wing_panel", "mesh": wing_panel_mesh, "translation": [0.0, 0.116, 0.190]},
        {"name": "wing_left_stanchion", "mesh": wing_stanchion_mesh, "translation": [-0.055, 0.082, 0.155]},
        {"name": "wing_right_stanchion", "mesh": wing_stanchion_mesh, "translation": [0.055, 0.082, 0.155]},
        {"name": "front_bumper", "children": [18, 19]},
        {"name": "front_bumper_bar", "mesh": bumper_bar_mesh, "translation": [0.0, -0.006, -0.179]},
        {"name": "front_bumper_loop", "mesh": bumper_upright_mesh, "translation": [0.0, 0.018, -0.183]},
        {"name": "skid_plate", "mesh": skid_plate_mesh, "translation": [0.0, -0.022, 0.016]},
        {"name": "shock_front_left", "mesh": shock_coil_mesh, "translation": [-0.068, 0.022, -0.096]},
        {"name": "shock_front_right", "mesh": shock_coil_mesh, "translation": [0.068, 0.022, -0.096]},
        {"name": "shock_rear_left", "mesh": shock_coil_mesh, "translation": [-0.068, 0.024, 0.104]},
        {"name": "shock_rear_right", "mesh": shock_coil_mesh, "translation": [0.068, 0.024, 0.104]},
        {"name": "front_left_arm", "mesh": suspension_arm_mesh, "translation": [-0.058, -0.020, -0.100]},
        {"name": "front_right_arm", "mesh": suspension_arm_mesh, "translation": [0.058, -0.020, -0.100]},
        {"name": "rear_left_arm", "mesh": suspension_arm_mesh, "translation": [-0.058, -0.020, 0.100]},
        {"name": "rear_right_arm", "mesh": suspension_arm_mesh, "translation": [0.058, -0.020, 0.100]},
        {"name": "body_pin_front", "mesh": hub_mesh, "translation": [-0.038, 0.044, -0.120]},
        {"name": "body_pin_rear", "mesh": hub_mesh, "translation": [0.038, 0.044, 0.100]},
        {"name": "wheel_front_left", "translation": [-0.08, -0.015, -0.10], "children": [32]},
        {"name": "wheel_mesh", "mesh": tire_mesh, "children": [33, 34, 35]},
        {"name": "rim_outer", "mesh": rim_mesh, "translation": [0.0, -0.019, 0.0]},
        {"name": "rim_inner", "mesh": rim_mesh, "translation": [0.0, 0.019, 0.0]},
        {"name": "hub_cap", "mesh": hub_mesh, "translation": [0.0, -0.022, 0.0]},
        {"name": "wheel_front_right", "translation": [0.08, -0.015, -0.10], "children": [37]},
        {"name": "wheel_mesh", "mesh": tire_mesh, "children": [38, 39, 40]},
        {"name": "rim_outer", "mesh": rim_mesh, "translation": [0.0, 0.019, 0.0]},
        {"name": "rim_inner", "mesh": rim_mesh, "translation": [0.0, -0.019, 0.0]},
        {"name": "hub_cap", "mesh": hub_mesh, "translation": [0.0, 0.022, 0.0]},
        {"name": "wheel_rear_left", "translation": [-0.08, -0.015, 0.10], "children": [42]},
        {"name": "wheel_mesh", "mesh": tire_mesh, "children": [43, 44, 45]},
        {"name": "rim_outer", "mesh": rim_mesh, "translation": [0.0, -0.019, 0.0]},
        {"name": "rim_inner", "mesh": rim_mesh, "translation": [0.0, 0.019, 0.0]},
        {"name": "hub_cap", "mesh": hub_mesh, "translation": [0.0, -0.022, 0.0]},
        {"name": "wheel_rear_right", "translation": [0.08, -0.015, 0.10], "children": [47]},
        {"name": "wheel_mesh", "mesh": tire_mesh, "children": [48, 49, 50]},
        {"name": "rim_outer", "mesh": rim_mesh, "translation": [0.0, 0.019, 0.0]},
        {"name": "rim_inner", "mesh": rim_mesh, "translation": [0.0, -0.019, 0.0]},
        {"name": "hub_cap", "mesh": hub_mesh, "translation": [0.0, 0.022, 0.0]},
        {"name": "body_stripe", "mesh": paint_stripe_mesh, "translation": [0.0, 0.052, -0.050]},
        {"name": "fender_flares", "mesh": fender_flare_mesh_index},
        {"name": "fender_lips", "mesh": fender_lip_mesh_index},
        {"name": "headlights", "mesh": headlight_mesh_index},
        {"name": "tail_lights", "mesh": tail_light_mesh_index},
        {"name": "front_grille", "mesh": grille_mesh_index},
        {"name": "side_number_plates", "mesh": side_number_plate_mesh_index},
        {"name": "side_number_marks", "mesh": side_number_mark_mesh_index},
        {"name": "body_vents", "mesh": vent_mesh_index},
        {"name": "antenna", "mesh": antenna_mesh_index, "translation": [0.052, 0.115, 0.063]},
    ]
    detail_nodes = [
        {"name": "roll_cage_detail", "mesh": roll_cage_detail_mesh_index},
        {"name": "suspension_a_arm_detail", "mesh": suspension_a_arm_detail_mesh_index},
        {"name": "shock_hardware", "mesh": shock_hardware_mesh_index},
        {"name": "exhaust", "mesh": exhaust_mesh_index},
    ]
    detail_start_index = len(nodes)
    nodes.extend(detail_nodes)
    nodes[0]["children"].extend(range(detail_start_index, len(nodes)))

    bin_chunk = pad4(bytes(binary), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_vehicle_glbs.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "buffers": [{"byteLength": len(bin_chunk)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    json_chunk = pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    total_length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with path.open("wb") as file:
        file.write(struct.pack("<4sII", b"glTF", 2, total_length))
        file.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        file.write(json_chunk)
        file.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        file.write(bin_chunk)


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    output_path = out_dir / "rc_buggy.glb"
    write_glb(output_path)
    print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
