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


def write_glb_parts(path, asset_name, surface_id, parts):
    node_name = asset_name + "__surf_" + surface_id
    bin_data = bytearray()
    buffer_views = []
    accessors = []
    primitives = []
    materials = []
    for part_index, mesh_part in enumerate(parts):
        vertices, indices, color, part_name = mesh_part
        position_data = pack_positions(vertices)
        index_data = pack_indices(indices)
        position_offset = len(bin_data)
        bin_data.extend(position_data)
        index_offset = len(bin_data)
        bin_data.extend(index_data)
        padding = (-len(bin_data)) % 4
        if padding:
            bin_data.extend(b"\0" * padding)
        mins, maxs = bounds(vertices)
        position_view = len(buffer_views)
        index_view = position_view + 1
        position_accessor = len(accessors)
        index_accessor = position_accessor + 1
        buffer_views.extend([
            {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
            {"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963},
        ])
        accessors.extend([
            {
                "bufferView": position_view,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC3",
                "min": mins,
                "max": maxs,
            },
            {
                "bufferView": index_view,
                "byteOffset": 0,
                "componentType": 5123,
                "count": len(indices),
                "type": "SCALAR",
                "min": [min(indices)],
                "max": [max(indices)],
            },
        ])
        primitives.append({
            "attributes": {"POSITION": position_accessor},
            "indices": index_accessor,
            "mode": 4,
            "material": part_index,
        })
        materials.append({
            "name": part_name + "_mat",
            "pbrMetallicRoughness": {
                "baseColorFactor": color,
                "roughnessFactor": 0.85,
                "metallicFactor": 0.0,
            },
        })
    bin_chunk = pad4(bytes(bin_data), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_feature_glbs.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": node_name, "mesh": 0}],
        "meshes": [{
            "name": node_name,
            "primitives": primitives,
        }],
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


def write_glb(path, asset_name, surface_id, vertices, indices, color):
    write_glb_parts(path, asset_name, surface_id, [part((vertices, indices), color, asset_name)])


def part(mesh, color, part_name):
    vertices, indices = mesh
    return vertices, indices, color, part_name


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
    return [
        part(box(0.9, 0.048, 0.24), [0.48, 0.31, 0.18, 1.0], "boardwalk_segment_plank"),
        part(merge([
            transformed(box(0.9, 0.012, 0.035), (0.0, 0.048, -0.085)),
            transformed(box(0.9, 0.012, 0.035), (0.0, 0.048, 0.085)),
        ]), [0.26, 0.16, 0.08, 1.0], "boardwalk_segment_seams"),
    ]


def culvert_pipe_parts():
    return [
        part(pipe(0.325, 1.2, 24), [0.35, 0.36, 0.35, 1.0], "culvert_pipe_body"),
        part(merge([
            transformed(pipe(0.34, 0.08, 24), (0.0, 0.0, -0.56)),
            transformed(pipe(0.34, 0.08, 24), (0.0, 0.0, 0.56)),
        ]), [0.20, 0.21, 0.20, 1.0], "culvert_pipe_rims"),
    ]


def log_ramp_parts():
    return [
        part(wedge(0.42, 0.20, 1.15), [0.34, 0.20, 0.10, 1.0], "log_ramp_body"),
        part(transformed(wedge(0.30, 0.025, 0.95), (0.0, 0.195, 0.02)), [0.52, 0.34, 0.18, 1.0], "log_ramp_highlight"),
    ]


def stepping_stone_parts():
    return [
        part(cylinder(0.24, 0.068, 14), [0.36, 0.37, 0.35, 1.0], "stepping_stone_base"),
        part(transformed(cylinder(0.21, 0.012, 14), (0.0, 0.068, 0.0)), [0.52, 0.53, 0.50, 1.0], "stepping_stone_wet_top"),
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
        write_glb_parts(output_path, asset_name, surface_id, parts)
        print(f"wrote: {output_path}")


if __name__ == "__main__":
    main()
