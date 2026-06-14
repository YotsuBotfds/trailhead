#!/usr/bin/env python3
import argparse
import json
import math
import struct
import zlib
from pathlib import Path

OUT_DIR = Path("assets/models/terrain")
GLB_FILENAME = "cedar_hollow_heightmesh.glb"
SURFACE_ID_FILENAME = "cedar_hollow_surface_id.png"


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead Cedar Hollow terrain assets.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated terrain assets.")
    return parser.parse_args()

X_MIN = -5.5
X_MAX = 5.5
Z_MIN = -10.6
Z_MAX = 1.6
GRID_X = 65
GRID_Z = 73
SURFACE_MAP_SIZE = 256

SURFACES = [
    ("packed_gravel", 1, [0.42, 0.38, 0.32, 1.0]),
    ("packed_dirt", 2, [0.35, 0.23, 0.14, 1.0]),
    ("tall_grass", 3, [0.25, 0.38, 0.17, 1.0]),
    ("mud", 4, [0.18, 0.12, 0.08, 1.0]),
    ("loose_rock", 5, [0.34, 0.34, 0.31, 1.0]),
    ("wet_stone", 6, [0.22, 0.30, 0.32, 1.0]),
    ("wood_plank", 7, [0.43, 0.27, 0.13, 1.0]),
]
SURFACE_INDEX = {name: index for name, index, _color in SURFACES}
SURFACE_COLORS = {name: color for name, _index, color in SURFACES}

REGIONS = [
    ("trailhead_gravel", "packed_gravel", 0.0, 0.75, 2.0, 1.5, 0.0),
    ("log_ramp_apron", "tall_grass", 1.78, 0.62, 1.6, 1.1, 0.0),
    ("main_trail_00", "packed_dirt", 0.0, -2.4, 1.2, 4.8, 0.0),
    ("old_cedar_pad", "packed_dirt", 0.0, -5.3, 2.0, 1.2, 0.0),
    ("meadow_left", "tall_grass", -1.7, -2.5, 2.0, 5.5, 0.0),
    ("meadow_right", "tall_grass", 1.7, -2.0, 2.0, 4.4, 0.0),
    ("culvert_spur", "packed_dirt", -2.2, -1.75, 4.8, 1.6, 0.0),
    ("culvert_mouth_floor", "packed_dirt", -4.35, -3.05, 1.7, 3.0, 0.0),
    ("outcrop_climb", "loose_rock", -1.2, -7.8, 4.6, 4.6, 0.22),
    ("switchback_entry_bridge", "packed_dirt", 0.25, -8.0, 1.8, 1.0, 0.36),
    ("switchback_outer_run", "packed_dirt", 1.55, -6.6, 1.4, 2.6, 0.24),
    ("switchback_lower_landing", "packed_dirt", 0.95, -5.25, 1.8, 1.4, 0.17),
    ("overlook_ridge_pad", "loose_rock", -2.3, -9.1, 3.8, 2.4, 0.36),
    ("bog_approach", "packed_dirt", 1.4, -5.25, 2.0, 1.0, -0.02),
    ("bog_bottom", "mud", 2.8, -5.5, 2.4, 2.4, -0.04),
    ("boardwalk_creek_connector", "mud", 3.9, -4.75, 2.2, 2.6, -0.04),
    ("creek_bank", "mud", 3.2, -6.85, 2.2, 1.9, -0.05),
    ("wet_stone_crossing", "wet_stone", 4.2, -7.35, 3.0, 2.9, -0.01),
    ("boardwalk", "wood_plank", 3.25, -3.35, 1.4, 2.6, 0.03),
]


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


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 0.0
    t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def gaussian(value, center, width):
    delta = (value - center) / max(width, 0.001)
    return math.exp(-delta * delta)


def region_weight(x, z, region):
    _name, _surface, cx, cz, sx, sz, _height = region
    dx = abs(x - cx) - sx * 0.5
    dz = abs(z - cz) - sz * 0.5
    outside = max(dx, dz)
    return 1.0 - smoothstep(-0.05, 0.55, outside)


def terrain_height(x, z):
    height = -0.035
    height += 0.05 * gaussian(x, -4.7, 0.9) * gaussian(z, -2.5, 5.2)
    height += 0.05 * gaussian(x, 4.9, 0.9) * gaussian(z, -3.7, 5.2)
    height += 0.10 * gaussian(z, -10.0, 1.5)
    height += 0.12 * gaussian(x, -2.0, 2.2) * gaussian(z, -8.8, 1.8)
    height += 0.20 * smoothstep(-7.2, -8.7, z) * gaussian(x, -1.3, 2.4)
    height += 0.10 * gaussian(x, 1.4, 1.5) * gaussian(z, -6.1, 2.0)
    height -= 0.07 * gaussian(x, 3.5, 1.8) * gaussian(z, -6.0, 2.0)
    for region in REGIONS:
        target_height = region[6]
        weight = region_weight(x, z, region)
        height = height * (1.0 - weight * 0.55) + target_height * (weight * 0.55)
    ripple = math.sin(x * 3.1 + z * 1.7) * 0.006 + math.sin(x * 1.3 - z * 2.1) * 0.004
    return height + ripple


def surface_at(x, z):
    best_surface = "tall_grass"
    best_weight = 0.0
    for region in REGIONS:
        weight = region_weight(x, z, region)
        if weight > best_weight:
            best_weight = weight
            best_surface = region[1]
    return best_surface


def normalize(vector):
    length = math.sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2])
    if length <= 0.000001:
        return (0.0, 1.0, 0.0)
    return (vector[0] / length, vector[1] / length, vector[2] / length)


def subtract(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def build_mesh():
    vertices = []
    uvs = []
    for z_index in range(GRID_Z):
        z_t = float(z_index) / float(GRID_Z - 1)
        z = Z_MIN + (Z_MAX - Z_MIN) * z_t
        for x_index in range(GRID_X):
            x_t = float(x_index) / float(GRID_X - 1)
            x = X_MIN + (X_MAX - X_MIN) * x_t
            vertices.append((x, terrain_height(x, z), z))
            uvs.append((x_t, 1.0 - z_t))

    indices_by_surface = {name: [] for name, _index, _color in SURFACES}
    for z_index in range(GRID_Z - 1):
        for x_index in range(GRID_X - 1):
            i0 = z_index * GRID_X + x_index
            i1 = i0 + 1
            i2 = i0 + GRID_X
            i3 = i2 + 1
            cx = (vertices[i0][0] + vertices[i3][0]) * 0.5
            cz = (vertices[i0][2] + vertices[i3][2]) * 0.5
            surface = surface_at(cx, cz)
            indices_by_surface[surface].extend([i0, i2, i1, i1, i2, i3])

    normals = [(0.0, 0.0, 0.0) for _vertex in vertices]
    for indices in indices_by_surface.values():
        for index in range(0, len(indices), 3):
            a_index = indices[index]
            b_index = indices[index + 1]
            c_index = indices[index + 2]
            a = vertices[a_index]
            b = vertices[b_index]
            c = vertices[c_index]
            normal = cross(subtract(b, a), subtract(c, a))
            normals[a_index] = add(normals[a_index], normal)
            normals[b_index] = add(normals[b_index], normal)
            normals[c_index] = add(normals[c_index], normal)
    normals = [normalize(normal) for normal in normals]
    return vertices, normals, uvs, indices_by_surface


def pack_vec3(values):
    return b"".join(struct.pack("<fff", value[0], value[1], value[2]) for value in values)


def pack_vec2(values):
    return b"".join(struct.pack("<ff", value[0], value[1]) for value in values)


def pack_indices(indices):
    return b"".join(struct.pack("<H", index) for index in indices)


def bounds(vertices):
    mins = [min(vertex[index] for vertex in vertices) for index in range(3)]
    maxs = [max(vertex[index] for vertex in vertices) for index in range(3)]
    return mins, maxs


def write_glb(path):
    vertices, normals, uvs, indices_by_surface = build_mesh()
    binary = bytearray()

    position_data = pack_vec3(vertices)
    normal_data = pack_vec3(normals)
    uv_data = pack_vec2(uvs)
    position_offset = append_aligned(binary, position_data)
    normal_offset = append_aligned(binary, normal_data)
    uv_offset = append_aligned(binary, uv_data)

    buffer_views = [
        {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
        {"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_data), "target": 34962},
        {"buffer": 0, "byteOffset": uv_offset, "byteLength": len(uv_data), "target": 34962},
    ]
    mins, maxs = bounds(vertices)
    accessors = [
        {
            "bufferView": 0,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(vertices),
            "type": "VEC3",
            "min": mins,
            "max": maxs,
        },
        {
            "bufferView": 1,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(normals),
            "type": "VEC3",
        },
        {
            "bufferView": 2,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(uvs),
            "type": "VEC2",
        },
    ]

    primitives = []
    for material_index, (surface_name, _surface_index, _color) in enumerate(SURFACES):
        indices = indices_by_surface[surface_name]
        if not indices:
            continue
        index_data = pack_indices(indices)
        index_offset = append_aligned(binary, index_data)
        buffer_views.append({"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963})
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
        primitives.append(
            {
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": len(accessors) - 1,
                "mode": 4,
                "material": material_index,
            }
        )

    bin_chunk = pad4(bytes(binary), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_heightmesh_assets.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "cedar_hollow_heightmesh", "mesh": 0}],
        "meshes": [{"name": "cedar_hollow_heightmesh", "primitives": primitives}],
        "materials": [
            {
                "name": "terrain_mat_" + surface_name,
                "pbrMetallicRoughness": {
                    "baseColorFactor": SURFACE_COLORS[surface_name],
                    "roughnessFactor": 1.0,
                    "metallicFactor": 0.0,
                },
            }
            for surface_name, _surface_index, _color in SURFACES
        ],
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


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_surface_id_png(path):
    rows = []
    for y in range(SURFACE_MAP_SIZE):
        z_t = float(y) / float(SURFACE_MAP_SIZE - 1)
        z = Z_MAX + (Z_MIN - Z_MAX) * z_t
        row = bytearray([0])
        for x in range(SURFACE_MAP_SIZE):
            x_t = float(x) / float(SURFACE_MAP_SIZE - 1)
            world_x = X_MIN + (X_MAX - X_MIN) * x_t
            surface = surface_at(world_x, z)
            row.append(SURFACE_INDEX[surface])
        rows.append(bytes(row))
    raw = b"".join(rows)
    header = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", SURFACE_MAP_SIZE, SURFACE_MAP_SIZE, 8, 0, 0, 0, 0)
    with path.open("wb") as file:
        file.write(header)
        file.write(png_chunk(b"IHDR", ihdr))
        file.write(png_chunk(b"IDAT", zlib.compress(raw, 9)))
        file.write(png_chunk(b"IEND", b""))


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    glb_path = out_dir / GLB_FILENAME
    surface_id_path = out_dir / SURFACE_ID_FILENAME
    write_glb(glb_path)
    write_surface_id_png(surface_id_path)
    print(f"wrote: {glb_path}")
    print(f"wrote: {surface_id_path}")


if __name__ == "__main__":
    main()
