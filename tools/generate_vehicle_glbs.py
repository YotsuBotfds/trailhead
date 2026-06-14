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


def write_glb(path):
    mesh_specs = [
        ("body", box(0.145, 0.052, 0.235), [0.93, 0.18, 0.07, 1.0]),
        ("nose", wedge(0.115, 0.034, 0.105), [0.98, 0.33, 0.09, 1.0]),
        ("top_deck", box(0.105, 0.010, 0.155), [0.080, 0.086, 0.098, 1.0]),
        ("side_panel", box(0.006, 0.042, 0.205), [0.94, 0.22, 0.08, 1.0]),
        ("canopy", wedge(0.082, 0.034, 0.088), [0.42, 0.50, 0.56, 0.58]),
        ("paint_stripe", box(0.026, 0.004, 0.178), [0.93, 0.88, 0.75, 1.0]),
        ("cage_side", box(0.010, 0.080, 0.170), [0.060, 0.064, 0.072, 1.0]),
        ("cage_top", box(0.128, 0.010, 0.168), [0.060, 0.064, 0.072, 1.0]),
        ("cage_crossbar", box(0.128, 0.010, 0.012), [0.060, 0.064, 0.072, 1.0]),
        ("wing_panel", box(0.178, 0.012, 0.058), [0.060, 0.064, 0.072, 1.0]),
        ("wing_stanchion", box(0.012, 0.056, 0.012), [0.060, 0.064, 0.072, 1.0]),
        ("bumper_bar", box(0.166, 0.018, 0.016), [0.060, 0.064, 0.072, 1.0]),
        ("bumper_upright", box(0.012, 0.040, 0.014), [0.060, 0.064, 0.072, 1.0]),
        ("skid_plate", box(0.118, 0.008, 0.250), [0.10, 0.105, 0.115, 1.0]),
        ("shock_coil", cylinder_y(0.006, 0.058, 12), [0.74, 0.70, 0.56, 1.0]),
        ("suspension_arm", box(0.074, 0.006, 0.012), [0.030, 0.032, 0.036, 1.0]),
        ("wheel_tire", treaded_tire(0.031, 0.034, 24, 12), [0.020, 0.020, 0.023, 1.0]),
        ("wheel_rim", cylinder_y(0.017, 0.004, 18), [0.16, 0.17, 0.18, 1.0]),
        ("wheel_hub", cylinder_y(0.008, 0.006, 14), [0.76, 0.70, 0.54, 1.0]),
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
    nodes = [
        {"name": "rc_buggy", "children": [1, 2, 3, 4, 5, 6, 7, 13, 17, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 36, 41, 46, 51]},
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
