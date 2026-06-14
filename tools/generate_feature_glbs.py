#!/usr/bin/env python3
import argparse
import json
import math
import struct
from pathlib import Path

OUT_DIR = Path("assets/models/features")


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead feature GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated feature GLBs.")
    return parser.parse_args()


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


def write_glb(path, asset_name, surface_id, vertices, indices, color):
    position_data = pack_positions(vertices)
    index_data = pack_indices(indices)
    position_offset = 0
    index_offset = len(position_data)
    bin_chunk = pad4(position_data + index_data, b"\0")
    mins, maxs = bounds(vertices)
    node_name = asset_name + "__surf_" + surface_id
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_feature_glbs.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": node_name, "mesh": 0}],
        "meshes": [{
            "name": node_name,
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
                "roughnessFactor": 0.85,
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


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    assets = [
        ("boardwalk_segment", "wood_plank", box(0.9, 0.06, 0.24), [0.46, 0.30, 0.18, 1.0]),
        ("culvert_pipe", "packed_dirt", pipe(0.34, 1.2, 24), [0.35, 0.36, 0.35, 1.0]),
        ("log_ramp", "wood_plank", wedge(0.42, 0.22, 1.15), [0.38, 0.23, 0.12, 1.0]),
        ("stepping_stone", "wet_stone", cylinder(0.24, 0.08, 14), [0.42, 0.43, 0.40, 1.0]),
    ]
    for asset_name, surface_id, mesh, color in assets:
        vertices, indices = mesh
        output_path = out_dir / (asset_name + ".glb")
        write_glb(output_path, asset_name, surface_id, vertices, indices, color)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
