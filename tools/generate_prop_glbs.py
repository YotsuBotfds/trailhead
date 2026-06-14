#!/usr/bin/env python3
import json
import math
import struct
from pathlib import Path

OUT_DIR = Path("assets/models/props")


def pad4(data, pad_byte=b" "):
    padding = (-len(data)) % 4
    if padding:
        data += pad_byte * padding
    return data


def pack_positions(vertices):
    return b"".join(struct.pack("<fff", vertex[0], vertex[1], vertex[2]) for vertex in vertices)


def pack_indices(indices):
    return b"".join(struct.pack("<H", index) for index in indices)


def bounds(vertices):
    mins = [min(vertex[index] for vertex in vertices) for index in range(3)]
    maxs = [max(vertex[index] for vertex in vertices) for index in range(3)]
    return mins, maxs


def write_glb(path, asset_name, vertices, indices, color):
    position_data = pack_positions(vertices)
    index_data = pack_indices(indices)
    position_offset = 0
    index_offset = len(position_data)
    bin_chunk = pad4(position_data + index_data, b"\0")
    mins, maxs = bounds(vertices)
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_prop_glbs.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": asset_name, "mesh": 0}],
        "meshes": [{
            "name": asset_name,
            "primitives": [{
                "attributes": {"POSITION": 0},
                "indices": 1,
                "mode": 4,
                "material": 0,
            }],
        }],
        "materials": [{
            "name": asset_name + "_mat",
            "pbrMetallicRoughness": {
                "baseColorFactor": color,
                "roughnessFactor": 0.88,
                "metallicFactor": 0.0,
            },
        }],
        "buffers": [{"byteLength": len(bin_chunk)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
            {"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963},
        ],
        "accessors": [
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
                "componentType": 5123,
                "count": len(indices),
                "type": "SCALAR",
                "min": [min(indices)],
                "max": [max(indices)],
            },
        ],
    }
    json_chunk = pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    total_length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with path.open("wb") as file:
        file.write(struct.pack("<4sII", b"glTF", 2, total_length))
        file.write(struct.pack("<II", len(json_chunk), 0x4E4F534A))
        file.write(json_chunk)
        file.write(struct.pack("<II", len(bin_chunk), 0x004E4942))
        file.write(bin_chunk)


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


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    assets = [
        ("trail_sign", trail_sign(), [0.45, 0.29, 0.16, 1.0]),
        ("picnic_table", picnic_table(), [0.42, 0.26, 0.14, 1.0]),
        ("old_cedar_stump", old_cedar_stump(), [0.32, 0.20, 0.11, 1.0]),
        ("fire_ring", fire_ring(), [0.30, 0.28, 0.24, 1.0]),
        ("hiking_boot", hiking_boot(), [0.18, 0.12, 0.08, 1.0]),
        ("water_bottle", water_bottle(), [0.22, 0.50, 0.62, 1.0]),
    ]
    for asset_name, mesh, color in assets:
        vertices, indices = mesh
        output_path = OUT_DIR / (asset_name + ".glb")
        write_glb(output_path, asset_name, vertices, indices, color)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
