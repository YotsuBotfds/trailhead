#!/usr/bin/env python3
import argparse
import json
import math
import random
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from simple_glb_writer import (  # noqa: E402
    append_aligned,
    bounds,
    compute_normals,
    compute_uvs,
    pack_indices,
    pack_normals,
    pack_positions,
    pack_uvs,
    pad4,
)

OUT_DIR = Path("assets/models/foliage")
GENERATOR_NAME = "Trailhead gen_foliage_species_glb.py"
SEED = 20260623
ROUGHNESS = 0.88
OPAQUE = "OPAQUE"
MASK = "MASK"


@dataclass(frozen=True)
class MeshPart:
    vertices: list[tuple[float, float, float]]
    indices: list[int]
    color: tuple[float, float, float, float]
    name: str
    alpha_mode: str = OPAQUE
    double_sided: bool = False
    alpha_cutoff: float = 0.45


@dataclass(frozen=True)
class LodMesh:
    name: str
    parts: list[MeshPart]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate deterministic Zion riparian foliage GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory for generated GLBs.")
    parser.add_argument(
        "--asset-stage",
        choices=["candidate", "final"],
        default="candidate",
        help="Write prototype candidate names or promoted final source names.",
    )
    parser.add_argument(
        "--species",
        choices=["all", "cottonwood", "willow"],
        default="all",
        help="Species to generate.",
    )
    return parser.parse_args()


def vec_add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vec_sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vec_mul(a: tuple[float, float, float], scalar: float) -> tuple[float, float, float]:
    return (a[0] * scalar, a[1] * scalar, a[2] * scalar)


def vec_dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vec_cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def vec_len(a: tuple[float, float, float]) -> float:
    return math.sqrt(vec_dot(a, a))


def vec_norm(a: tuple[float, float, float], fallback: tuple[float, float, float] = (0.0, 1.0, 0.0)) -> tuple[float, float, float]:
    length = vec_len(a)
    if length <= 0.000001:
        return fallback
    return (a[0] / length, a[1] / length, a[2] / length)


def radial(angle_degrees: float) -> tuple[float, float, float]:
    angle = math.radians(angle_degrees)
    return (math.cos(angle), 0.0, math.sin(angle))


def lerp_vec(a: tuple[float, float, float], b: tuple[float, float, float], t: float) -> tuple[float, float, float]:
    return (
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    )


def merge_meshes(meshes: list[tuple[list[tuple[float, float, float]], list[int]]]) -> tuple[list[tuple[float, float, float]], list[int]]:
    vertices: list[tuple[float, float, float]] = []
    indices: list[int] = []
    for mesh_vertices, mesh_indices in meshes:
        base_index = len(vertices)
        vertices.extend(mesh_vertices)
        indices.extend(index + base_index for index in mesh_indices)
    return vertices, indices


def mesh_part(
    mesh: tuple[list[tuple[float, float, float]], list[int]],
    color: tuple[float, float, float, float],
    name: str,
    alpha_mode: str = OPAQUE,
    double_sided: bool = False,
) -> MeshPart:
    vertices, indices = mesh
    return MeshPart(vertices, indices, color, name, alpha_mode, double_sided)


def branch_basis(start: tuple[float, float, float], end: tuple[float, float, float]) -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float], float]:
    axis = vec_sub(end, start)
    length = vec_len(axis)
    if length <= 0.000001:
        raise ValueError("zero length branch")
    tangent = vec_norm(axis)
    reference = (0.0, 1.0, 0.0)
    if abs(vec_dot(tangent, reference)) > 0.92:
        reference = (1.0, 0.0, 0.0)
    bitangent = vec_norm(vec_cross(tangent, reference), (1.0, 0.0, 0.0))
    normal = vec_norm(vec_cross(bitangent, tangent), (0.0, 0.0, 1.0))
    return tangent, bitangent, normal, length


def tapered_branch(
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius_start: float,
    radius_end: float,
    segments: int,
    wobble: float,
) -> tuple[list[tuple[float, float, float]], list[int]]:
    _tangent, bitangent, normal, _length = branch_basis(start, end)
    vertices: list[tuple[float, float, float]] = []
    for ring_index, center in enumerate((start, end)):
        radius = radius_start if ring_index == 0 else radius_end
        for segment in range(segments):
            angle = math.tau * float(segment) / float(segments)
            ripple = 1.0 + math.sin(angle * 3.0 + float(ring_index) * 0.73) * wobble
            offset = vec_add(vec_mul(bitangent, math.cos(angle) * radius * ripple), vec_mul(normal, math.sin(angle) * radius * ripple))
            vertices.append(vec_add(center, offset))
    bottom_center = len(vertices)
    top_center = bottom_center + 1
    vertices.append(start)
    vertices.append(end)
    indices: list[int] = []
    for segment in range(segments):
        next_segment = (segment + 1) % segments
        bottom_a = segment
        bottom_b = next_segment
        top_a = segment + segments
        top_b = next_segment + segments
        indices.extend([bottom_a, bottom_b, top_b, bottom_a, top_b, top_a])
        indices.extend([bottom_center, bottom_b, bottom_a])
        indices.extend([top_center, top_a, top_b])
    return vertices, indices


def card_basis(yaw: float, pitch: float) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    normal = (
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch),
        math.sin(yaw) * math.cos(pitch),
    )
    normal = vec_norm(normal, (0.0, 0.0, 1.0))
    right = vec_norm(vec_cross((0.0, 1.0, 0.0), normal), (1.0, 0.0, 0.0))
    up = vec_norm(vec_cross(normal, right), (0.0, 1.0, 0.0))
    return right, up


def leaf_cards(
    centers: list[tuple[float, float, float]],
    rng: random.Random,
    width_range: tuple[float, float],
    height_range: tuple[float, float],
    pitch_range: tuple[float, float],
    narrow: bool,
) -> tuple[list[tuple[float, float, float]], list[int]]:
    vertices: list[tuple[float, float, float]] = []
    indices: list[int] = []
    for center in centers:
        yaw = rng.random() * math.tau
        pitch = math.radians(rng.uniform(pitch_range[0], pitch_range[1]))
        right, up = card_basis(yaw, pitch)
        width = rng.uniform(width_range[0], width_range[1])
        height = rng.uniform(height_range[0], height_range[1])
        base = len(vertices)
        if narrow:
            top = vec_add(center, vec_mul(up, height * 0.58))
            bottom = vec_sub(center, vec_mul(up, height * 0.42))
            vertices.extend([
                vec_add(bottom, vec_mul(right, -width * 0.36)),
                vec_add(bottom, vec_mul(right, width * 0.36)),
                vec_add(center, vec_add(vec_mul(right, width * 0.50), vec_mul(up, height * 0.10))),
                top,
                vec_add(center, vec_add(vec_mul(right, -width * 0.50), vec_mul(up, height * 0.10))),
            ])
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 4, base + 4, base + 2, base + 3])
        else:
            vertices.extend([
                vec_add(center, vec_add(vec_mul(right, -width * 0.50), vec_mul(up, -height * 0.50))),
                vec_add(center, vec_add(vec_mul(right, width * 0.50), vec_mul(up, -height * 0.50))),
                vec_add(center, vec_add(vec_mul(right, width * 0.50), vec_mul(up, height * 0.50))),
                vec_add(center, vec_add(vec_mul(right, -width * 0.50), vec_mul(up, height * 0.50))),
            ])
            indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    return vertices, indices


def crown_centers(
    rng: random.Random,
    count: int,
    radius_x: float,
    radius_z: float,
    y_min: float,
    y_max: float,
    flatten: float,
) -> list[tuple[float, float, float]]:
    centers: list[tuple[float, float, float]] = []
    for index in range(count):
        t = float(index) / float(max(count - 1, 1))
        angle = t * math.tau * 6.7 + rng.uniform(-0.22, 0.22)
        radial_t = math.sqrt(rng.random())
        x = math.cos(angle) * radius_x * radial_t * rng.uniform(0.78, 1.08)
        z = math.sin(angle) * radius_z * radial_t * rng.uniform(0.78, 1.08)
        canopy_t = max(0.0, 1.0 - (x / max(radius_x, 0.01)) ** 2 * 0.38 - (z / max(radius_z, 0.01)) ** 2 * 0.38)
        y = y_min + (y_max - y_min) * (flatten * rng.random() + (1.0 - flatten) * canopy_t)
        y += rng.uniform(-0.42, 0.38)
        centers.append((x, y, z))
    return centers


def cottonwood_trunk_center(y: float) -> tuple[float, float, float]:
    t = min(max(y / 13.0, 0.0), 1.0)
    return (0.38 * t + 0.18 * math.sin(t * math.pi * 1.12), y, -0.26 * t)


def build_cottonwood_lod0() -> LodMesh:
    rng = random.Random(SEED + 101)
    bark_meshes = []
    trunk_points = [
        cottonwood_trunk_center(0.0),
        cottonwood_trunk_center(3.8),
        cottonwood_trunk_center(7.4),
        cottonwood_trunk_center(11.2),
        cottonwood_trunk_center(13.1),
    ]
    trunk_radii = [0.48, 0.42, 0.32, 0.22, 0.14]
    for index in range(len(trunk_points) - 1):
        bark_meshes.append(tapered_branch(trunk_points[index], trunk_points[index + 1], trunk_radii[index], trunk_radii[index + 1], 12, 0.035))

    branch_ends: list[tuple[float, float, float]] = []
    branch_specs = [
        (5.8, 12.0, 6.8, 2.8, 0.24),
        (6.4, 92.0, 7.8, 3.0, 0.23),
        (6.9, 174.0, 6.4, 2.5, 0.22),
        (7.6, 248.0, 7.3, 2.9, 0.21),
        (8.4, 314.0, 6.6, 3.3, 0.20),
        (9.2, 48.0, 6.0, 4.5, 0.17),
        (10.0, 138.0, 5.4, 4.8, 0.16),
        (10.7, 222.0, 5.2, 4.2, 0.15),
        (11.5, 292.0, 4.8, 5.2, 0.13),
    ]
    for index, (height, angle_degrees, length, rise, radius) in enumerate(branch_specs):
        start = cottonwood_trunk_center(height)
        direction = radial(angle_degrees)
        mid = vec_add(start, vec_add(vec_mul(direction, length * 0.44), (0.0, rise * 0.38, 0.0)))
        end = vec_add(start, vec_add(vec_mul(direction, length), (0.0, rise, 0.0)))
        end = vec_add(end, (rng.uniform(-0.28, 0.28), rng.uniform(-0.20, 0.34), rng.uniform(-0.28, 0.28)))
        bark_meshes.append(tapered_branch(start, mid, radius, radius * 0.68, 10, 0.045))
        bark_meshes.append(tapered_branch(mid, end, radius * 0.68, radius * 0.28, 8, 0.050))
        branch_ends.append(end)
        for side_index, side_offset in enumerate((-38.0, 36.0)):
            side_start = lerp_vec(mid, end, 0.44 + 0.14 * float(side_index))
            side_dir = radial(angle_degrees + side_offset + rng.uniform(-6.0, 6.0))
            side_length = length * rng.uniform(0.26, 0.36)
            side_end = vec_add(side_start, vec_add(vec_mul(side_dir, side_length), (0.0, rng.uniform(0.7, 1.35), 0.0)))
            bark_meshes.append(tapered_branch(side_start, side_end, radius * 0.34, radius * 0.095, 6, 0.055))
            branch_ends.append(side_end)

    leaf_centers = crown_centers(rng, 620, 8.7, 7.8, 12.1, 24.1, 0.34)
    for end in branch_ends:
        for _copy in range(8):
            leaf_centers.append((
                end[0] + rng.uniform(-1.0, 1.0),
                end[1] + rng.uniform(-0.6, 1.1),
                end[2] + rng.uniform(-1.0, 1.0),
            ))
    leaf_mesh = leaf_cards(leaf_centers, rng, (0.28, 0.56), (0.34, 0.72), (-24.0, 32.0), False)
    return LodMesh("cottonwood_candidate_lod0", [
        mesh_part(merge_meshes(bark_meshes), (0.43, 0.36, 0.26, 1.0), "cottonwood_pale_furrowed_bark"),
        mesh_part(leaf_mesh, (0.42, 0.56, 0.16, 0.92), "cottonwood_summer_leaf_cards", MASK, True),
    ])


def build_cottonwood_lod1() -> LodMesh:
    rng = random.Random(SEED + 102)
    bark_meshes = []
    trunk_points = [
        cottonwood_trunk_center(0.0),
        cottonwood_trunk_center(6.2),
        cottonwood_trunk_center(11.8),
    ]
    trunk_radii = [0.44, 0.31, 0.14]
    for index in range(len(trunk_points) - 1):
        bark_meshes.append(tapered_branch(trunk_points[index], trunk_points[index + 1], trunk_radii[index], trunk_radii[index + 1], 8, 0.025))
    for height, angle_degrees, length, rise, radius in [
        (6.4, 35.0, 7.0, 3.2, 0.19),
        (7.2, 136.0, 7.2, 3.4, 0.18),
        (8.4, 240.0, 6.8, 3.1, 0.17),
        (9.5, 318.0, 5.6, 4.6, 0.15),
        (10.8, 74.0, 4.8, 5.1, 0.12),
    ]:
        start = cottonwood_trunk_center(height)
        end = vec_add(start, vec_add(vec_mul(radial(angle_degrees), length), (0.0, rise, 0.0)))
        bark_meshes.append(tapered_branch(start, end, radius, radius * 0.18, 6, 0.035))
    leaf_centers = crown_centers(rng, 115, 8.5, 7.4, 13.0, 23.6, 0.48)
    leaf_mesh = leaf_cards(leaf_centers, rng, (0.75, 1.38), (0.86, 1.62), (-18.0, 24.0), False)
    return LodMesh("cottonwood_candidate_lod1", [
        mesh_part(merge_meshes(bark_meshes), (0.38, 0.32, 0.24, 1.0), "cottonwood_lod1_bark"),
        mesh_part(leaf_mesh, (0.36, 0.48, 0.13, 0.90), "cottonwood_lod1_leaf_cards", MASK, True),
    ])


def willow_stem_end(index: int, count: int, rng: random.Random, height_scale: float) -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]:
    angle = math.tau * float(index) / float(count) + rng.uniform(-0.12, 0.12)
    base_radius = rng.uniform(0.05, 0.54)
    base = (math.cos(angle) * base_radius, 0.0, math.sin(angle) * base_radius)
    height = rng.uniform(6.4, 10.8) * height_scale
    lean_length = rng.uniform(1.8, 3.6) * height_scale
    direction = radial(math.degrees(angle) + rng.uniform(-18.0, 18.0))
    mid = vec_add(base, vec_add(vec_mul(direction, lean_length * 0.45), (0.0, height * 0.50, 0.0)))
    end = vec_add(base, vec_add(vec_mul(direction, lean_length), (0.0, height, 0.0)))
    return base, mid, end


def build_willow_lod0() -> LodMesh:
    rng = random.Random(SEED + 201)
    bark_meshes = []
    leaf_centers: list[tuple[float, float, float]] = []
    stem_count = 22
    for stem_index in range(stem_count):
        base, mid, end = willow_stem_end(stem_index, stem_count, rng, 1.0)
        radius = rng.uniform(0.045, 0.088)
        bark_meshes.append(tapered_branch(base, mid, radius, radius * 0.60, 7, 0.045))
        bark_meshes.append(tapered_branch(mid, end, radius * 0.60, radius * 0.18, 6, 0.055))
        stem_direction = math.degrees(math.atan2(end[2] - base[2], end[0] - base[0]))
        for side_index, side_offset in enumerate((-44.0, -18.0, 24.0, 58.0)):
            side_start = lerp_vec(mid, end, rng.uniform(0.18, 0.78))
            side_dir = radial(stem_direction + side_offset + rng.uniform(-10.0, 10.0))
            side_end = vec_add(side_start, vec_add(vec_mul(side_dir, rng.uniform(0.42, 1.05)), (0.0, rng.uniform(-0.32, 0.34), 0.0)))
            bark_meshes.append(tapered_branch(side_start, side_end, radius * 0.23, radius * 0.055, 5, 0.060))
            for _copy in range(9):
                leaf_centers.append((
                    side_end[0] + rng.uniform(-0.28, 0.28),
                    side_end[1] + rng.uniform(-0.48, 0.32),
                    side_end[2] + rng.uniform(-0.28, 0.28),
                ))
        for _copy in range(12):
            leaf_centers.append((
                end[0] + rng.uniform(-0.38, 0.38),
                end[1] + rng.uniform(-0.78, 0.22),
                end[2] + rng.uniform(-0.38, 0.38),
            ))
    leaf_mesh = leaf_cards(leaf_centers, rng, (0.10, 0.22), (0.50, 1.05), (-38.0, 14.0), True)
    return LodMesh("willow_candidate_lod0", [
        mesh_part(merge_meshes(bark_meshes), (0.31, 0.23, 0.14, 1.0), "willow_fine_bark_stems"),
        mesh_part(leaf_mesh, (0.32, 0.42, 0.22, 0.90), "willow_silvery_narrow_leaf_cards", MASK, True),
    ])


def build_willow_lod1() -> LodMesh:
    rng = random.Random(SEED + 202)
    bark_meshes = []
    leaf_centers: list[tuple[float, float, float]] = []
    stem_count = 11
    for stem_index in range(stem_count):
        base, _mid, end = willow_stem_end(stem_index, stem_count, rng, 0.92)
        radius = rng.uniform(0.05, 0.08)
        bark_meshes.append(tapered_branch(base, end, radius, radius * 0.16, 5, 0.040))
        for _copy in range(14):
            leaf_centers.append((
                end[0] * rng.uniform(0.72, 1.04) + rng.uniform(-0.72, 0.72),
                end[1] * rng.uniform(0.52, 1.00),
                end[2] * rng.uniform(0.72, 1.04) + rng.uniform(-0.72, 0.72),
            ))
    leaf_mesh = leaf_cards(leaf_centers, rng, (0.28, 0.55), (1.1, 2.3), (-28.0, 10.0), True)
    return LodMesh("willow_candidate_lod1", [
        mesh_part(merge_meshes(bark_meshes), (0.28, 0.21, 0.13, 1.0), "willow_lod1_stems"),
        mesh_part(leaf_mesh, (0.28, 0.37, 0.20, 0.88), "willow_lod1_leaf_cards", MASK, True),
    ])


def material_for_part(part: MeshPart) -> dict:
    material = {
        "name": part.name + "_mat",
        "pbrMetallicRoughness": {
            "baseColorFactor": list(part.color),
            "roughnessFactor": ROUGHNESS,
            "metallicFactor": 0.0,
        },
    }
    if part.double_sided:
        material["doubleSided"] = True
    if part.alpha_mode != OPAQUE:
        material["alphaMode"] = part.alpha_mode
        material["alphaCutoff"] = part.alpha_cutoff
    return material


def write_lod_glb(path: Path, asset_name: str, lods: list[LodMesh]) -> None:
    bin_data = bytearray()
    buffer_views = []
    accessors = []
    materials = []
    meshes = []
    for lod in lods:
        primitives = []
        for mesh_part in lod.parts:
            if max(mesh_part.indices, default=0) > 65535:
                raise ValueError(mesh_part.name + " exceeds uint16 index range")
            position_data = pack_positions(mesh_part.vertices)
            normal_data = pack_normals(compute_normals(mesh_part.vertices, mesh_part.indices))
            uv_data = pack_uvs(compute_uvs(mesh_part.vertices))
            index_data = pack_indices(mesh_part.indices)
            position_offset = append_aligned(bin_data, position_data)
            normal_offset = append_aligned(bin_data, normal_data)
            uv_offset = append_aligned(bin_data, uv_data)
            index_offset = append_aligned(bin_data, index_data, 2)
            mins, maxs = bounds(mesh_part.vertices)
            position_view = len(buffer_views)
            normal_view = position_view + 1
            uv_view = position_view + 2
            index_view = position_view + 3
            position_accessor = len(accessors)
            normal_accessor = position_accessor + 1
            uv_accessor = position_accessor + 2
            index_accessor = position_accessor + 3
            buffer_views.extend([
                {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
                {"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_data), "target": 34962},
                {"buffer": 0, "byteOffset": uv_offset, "byteLength": len(uv_data), "target": 34962},
                {"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963},
            ])
            accessors.extend([
                {
                    "bufferView": position_view,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": len(mesh_part.vertices),
                    "type": "VEC3",
                    "min": mins,
                    "max": maxs,
                },
                {
                    "bufferView": normal_view,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": len(mesh_part.vertices),
                    "type": "VEC3",
                },
                {
                    "bufferView": uv_view,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": len(mesh_part.vertices),
                    "type": "VEC2",
                },
                {
                    "bufferView": index_view,
                    "byteOffset": 0,
                    "componentType": 5123,
                    "count": len(mesh_part.indices),
                    "type": "SCALAR",
                    "min": [min(mesh_part.indices)],
                    "max": [max(mesh_part.indices)],
                },
            ])
            material_index = len(materials)
            materials.append(material_for_part(mesh_part))
            primitives.append({
                "attributes": {
                    "POSITION": position_accessor,
                    "NORMAL": normal_accessor,
                    "TEXCOORD_0": uv_accessor,
                },
                "indices": index_accessor,
                "mode": 4,
                "material": material_index,
            })
        meshes.append({"name": lod.name + "_mesh", "primitives": primitives})

    child_nodes = []
    nodes = [{"name": asset_name, "children": child_nodes}]
    for mesh_index, lod in enumerate(lods):
        child_nodes.append(len(nodes))
        nodes.append({"name": lod.name, "mesh": mesh_index})

    bin_chunk = pad4(bytes(bin_data), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": GENERATOR_NAME},
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
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as file:
        file.write(struct.pack("<4sII", b"glTF", 2, total_length))
        file.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        file.write(json_chunk)
        file.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        file.write(bin_chunk)


def triangle_count(lod: LodMesh) -> int:
    return sum(len(part.indices) // 3 for part in lod.parts)


def dimensions_for_lods(lods: list[LodMesh]) -> tuple[float, float, float]:
    all_vertices = [vertex for lod in lods for part in lod.parts for vertex in part.vertices]
    mins, maxs = bounds(all_vertices)
    return (maxs[0] - mins[0], maxs[1] - mins[1], maxs[2] - mins[2])


def grounded_lods(lods: list[LodMesh]) -> list[LodMesh]:
    all_vertices = [vertex for lod in lods for part in lod.parts for vertex in part.vertices]
    mins, _maxs = bounds(all_vertices)
    y_offset = -mins[1]
    if abs(y_offset) <= 0.000001:
        return lods
    grounded: list[LodMesh] = []
    for lod in lods:
        parts: list[MeshPart] = []
        for part in lod.parts:
            shifted_vertices = [(vertex[0], vertex[1] + y_offset, vertex[2]) for vertex in part.vertices]
            parts.append(MeshPart(
                shifted_vertices,
                part.indices,
                part.color,
                part.name,
                part.alpha_mode,
                part.double_sided,
                part.alpha_cutoff,
            ))
        grounded.append(LodMesh(lod.name, parts))
    return grounded


def renamed_lods(lods: list[LodMesh], source_prefix: str, target_prefix: str) -> list[LodMesh]:
    renamed: list[LodMesh] = []
    for lod in lods:
        lod_name = lod.name
        if lod_name.startswith(source_prefix):
            lod_name = target_prefix + lod_name[len(source_prefix):]
        renamed.append(LodMesh(lod_name, lod.parts))
    return renamed


def build_assets(species: str, asset_stage: str) -> list[tuple[str, list[LodMesh]]]:
    assets = []
    if species in ("all", "cottonwood"):
        cottonwood_lods = grounded_lods([build_cottonwood_lod0(), build_cottonwood_lod1()])
        if asset_stage == "final":
            cottonwood_lods = renamed_lods(cottonwood_lods, "cottonwood_candidate", "cottonwood")
            assets.append(("cottonwood", cottonwood_lods))
        else:
            assets.append(("cottonwood_candidate", cottonwood_lods))
    if species in ("all", "willow"):
        willow_lods = grounded_lods([build_willow_lod0(), build_willow_lod1()])
        if asset_stage == "final":
            willow_lods = renamed_lods(willow_lods, "willow_candidate", "willow")
            assets.append(("willow", willow_lods))
        else:
            assets.append(("willow_candidate", willow_lods))
    return assets


def main() -> None:
    args = parse_args()
    for asset_name, lods in build_assets(args.species, args.asset_stage):
        out_path = args.out_dir / (asset_name + ".glb")
        write_lod_glb(out_path, asset_name, lods)
        width, height, depth = dimensions_for_lods(lods)
        lod_report = ", ".join(lod.name + "=" + str(triangle_count(lod)) for lod in lods)
        print(
            "exported "
            + str(out_path)
            + " tris=("
            + lod_report
            + ") size_m=("
            + format(width, ".2f")
            + ", "
            + format(height, ".2f")
            + ", "
            + format(depth, ".2f")
            + ")"
        )


if __name__ == "__main__":
    main()
