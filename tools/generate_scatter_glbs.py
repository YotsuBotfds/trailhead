#!/usr/bin/env python3
import argparse
import json
import math
import struct
from pathlib import Path

OUT_DIR = Path("assets/models/scatter")


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead scatter GLBs.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated scatter GLBs.")
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


def write_glb(path, asset_name, vertices, indices, color):
    position_data = pack_positions(vertices)
    index_data = pack_indices(indices)
    position_offset = 0
    index_offset = len(position_data)
    bin_chunk = pad4(position_data + index_data, b"\0")
    mins, maxs = bounds(vertices)
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_scatter_glbs.py"},
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
                "roughnessFactor": 0.9,
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


def main():
    args = parse_args()
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    assets = [
        ("grass_tuft", grass_tuft(), [0.22, 0.37, 0.13, 1.0]),
        ("boulder_a", boulder_a(), [0.36, 0.36, 0.33, 1.0]),
        ("branch_a", branch_a(), [0.28, 0.17, 0.09, 1.0]),
        ("pinecone", pinecone(), [0.26, 0.15, 0.08, 1.0]),
        ("fern_clump", fern_clump(), [0.12, 0.33, 0.16, 1.0]),
        ("cattail", cattail(), [0.30, 0.22, 0.10, 1.0]),
        ("trail_blaze", trail_blaze(), [0.55, 0.32, 0.12, 1.0]),
    ]
    for asset_name, mesh, color in assets:
        vertices, indices = mesh
        output_path = out_dir / (asset_name + ".glb")
        write_glb(output_path, asset_name, vertices, indices, color)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
