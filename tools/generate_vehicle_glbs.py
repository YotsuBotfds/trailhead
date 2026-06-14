#!/usr/bin/env python3
import argparse
import json
import math
import struct
from pathlib import Path

from simple_glb_writer import compute_normals, compute_uvs, pack_normals, pack_uvs

OUT_DIR = Path("assets/models/vehicle")


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


def write_glb(path):
    mesh_specs = [
        ("body", box(0.16, 0.055, 0.28), [0.95, 0.16, 0.08, 1.0]),
        ("nose", wedge(0.12, 0.035, 0.10), [0.98, 0.28, 0.08, 1.0]),
        ("cage_left", box(0.012, 0.075, 0.16), [0.06, 0.06, 0.07, 1.0]),
        ("cage_right", box(0.012, 0.075, 0.16), [0.06, 0.06, 0.07, 1.0]),
        ("cage_top", box(0.13, 0.012, 0.16), [0.06, 0.06, 0.07, 1.0]),
        ("wheel_mesh", cylinder_y(0.03, 0.035, 18), [0.03, 0.03, 0.035, 1.0]),
    ]

    binary = bytearray()
    buffer_views = []
    accessors = []
    meshes = []
    materials = []
    for mesh_index, (mesh_name, mesh, color) in enumerate(mesh_specs):
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
                    "roughnessFactor": 0.82,
                    "metallicFactor": 0.0,
                },
            }
        )
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
    cage_left_mesh = 2
    cage_right_mesh = 3
    cage_top_mesh = 4
    wheel_mesh = 5
    nodes = [
        {"name": "rc_buggy", "children": [1, 2, 3, 7, 9, 11, 13]},
        {"name": "body", "mesh": body_mesh},
        {"name": "nose", "mesh": nose_mesh, "translation": [0.0, 0.01, -0.18]},
        {"name": "roll_cage", "children": [4, 5, 6]},
        {"name": "cage_left", "mesh": cage_left_mesh, "translation": [-0.055, 0.055, -0.02]},
        {"name": "cage_right", "mesh": cage_right_mesh, "translation": [0.055, 0.055, -0.02]},
        {"name": "cage_top", "mesh": cage_top_mesh, "translation": [0.0, 0.095, -0.02]},
        {"name": "wheel_front_left", "translation": [-0.08, -0.015, -0.10], "children": [8]},
        {"name": "wheel_mesh", "mesh": wheel_mesh},
        {"name": "wheel_front_right", "translation": [0.08, -0.015, -0.10], "children": [10]},
        {"name": "wheel_mesh", "mesh": wheel_mesh},
        {"name": "wheel_rear_left", "translation": [-0.08, -0.015, 0.10], "children": [12]},
        {"name": "wheel_mesh", "mesh": wheel_mesh},
        {"name": "wheel_rear_right", "translation": [0.08, -0.015, 0.10], "children": [14]},
        {"name": "wheel_mesh", "mesh": wheel_mesh},
    ]

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
