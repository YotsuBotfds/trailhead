#!/usr/bin/env python3
import argparse
import json
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_BLENDER = Path("/Applications/Blender.app/Contents/MacOS/Blender")
DEFAULT_SCAFFOLD = Path("assets/models/vehicle/rc_buggy.glb")
JSON_CHUNK_TYPE = 0x4E4F534A


BLENDER_SCRIPT = r'''
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_blender_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    parser = argparse.ArgumentParser(description="Socket a Trellis2 vehicle donor onto the Trailhead vehicle scaffold.")
    parser.add_argument("scaffold_glb")
    parser.add_argument("donor_glb")
    parser.add_argument("output_glb")
    parser.add_argument("--donor-node-name", default="trellis_body_shell")
    parser.add_argument("--donor-largest-dimension", type=float, default=0.38)
    parser.add_argument("--donor-bottom-y", type=float, default=-0.035)
    parser.add_argument("--donor-center-z", type=float, default=0.0)
    parser.add_argument("--max-donor-triangles", type=int, default=180000)
    return parser.parse_args(argv)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_scene(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [obj for obj in bpy.context.scene.objects if obj not in before]


def find_object(name):
    for obj in bpy.context.scene.objects:
        if obj.name == name:
            return obj
    return None


def bounds_for(objects):
    points = []
    for obj in objects:
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        raise RuntimeError("no mesh bounds found")
    bounds_min = Vector((
        min(point.x for point in points),
        min(point.y for point in points),
        min(point.z for point in points),
    ))
    bounds_max = Vector((
        max(point.x for point in points),
        max(point.y for point in points),
        max(point.z for point in points),
    ))
    return bounds_min, bounds_max


def triangle_count(obj):
    return sum(max(len(poly.vertices) - 2, 0) for poly in obj.data.polygons)


def decimate_if_needed(obj, max_triangles):
    current_triangles = triangle_count(obj)
    if max_triangles <= 0 or current_triangles <= max_triangles:
        return
    ratio = max(0.01, float(max_triangles) / float(current_triangles))
    modifier = obj.modifiers.new("candidate_decimate", "DECIMATE")
    modifier.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def add_uv_if_missing(obj):
    if obj.data.uv_layers:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def join_donor_meshes(imported_objects):
    meshes = [obj for obj in imported_objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("donor import produced no mesh objects")
    for obj in meshes:
        world_matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world_matrix
    for obj in imported_objects:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    if len(meshes) == 1:
        return meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    return bpy.context.object


def normalize_donor(obj, args):
    obj.name = args.donor_node_name
    obj.data.name = args.donor_node_name
    decimate_if_needed(obj, args.max_donor_triangles)
    add_uv_if_missing(obj)
    bpy.context.view_layer.update()
    bounds_min, bounds_max = bounds_for([obj])
    dimensions = bounds_max - bounds_min
    largest = max(dimensions.x, dimensions.y, dimensions.z)
    if largest <= 0.000001:
        raise RuntimeError("donor mesh has degenerate bounds")
    scale_factor = args.donor_largest_dimension / largest
    obj.scale = obj.scale * scale_factor
    bpy.context.view_layer.update()
    bounds_min, bounds_max = bounds_for([obj])
    center_x = (bounds_min.x + bounds_max.x) * 0.5
    center_z = (bounds_min.z + bounds_max.z) * 0.5
    obj.location.x -= center_x
    obj.location.y += args.donor_bottom_y - bounds_min.y
    obj.location.z += args.donor_center_z - center_z
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def main():
    args = parse_blender_args()
    clear_scene()
    import_scene(Path(args.scaffold_glb))
    root = find_object("rc_buggy")
    if root is None:
        raise RuntimeError("scaffold import did not produce rc_buggy root")
    donor_objects = import_scene(Path(args.donor_glb))
    donor = join_donor_meshes(donor_objects)
    normalize_donor(donor, args)
    donor.parent = root
    bpy.context.view_layer.update()
    Path(args.output_glb).parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output_glb),
        export_format="GLB",
        export_image_format="JPEG",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
    )


main()
'''


def parse_args():
    parser = argparse.ArgumentParser(description="Build a socket-safe Trellis2 vehicle candidate GLB.")
    parser.add_argument("donor_glb", type=Path, help="Cleaned Trellis2/body donor GLB.")
    parser.add_argument("output_glb", type=Path, help="Candidate GLB to write under assets/generated.")
    parser.add_argument("--scaffold-glb", type=Path, default=DEFAULT_SCAFFOLD, help="Socketed vehicle scaffold GLB.")
    parser.add_argument("--donor-node-name", default="trellis_body_shell")
    parser.add_argument("--donor-largest-dimension", type=float, default=0.38)
    parser.add_argument("--donor-bottom-y", type=float, default=-0.035)
    parser.add_argument("--donor-center-z", type=float, default=0.0)
    parser.add_argument("--max-donor-triangles", type=int, default=180000)
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    return parser.parse_args()


def pad4(data, pad_byte=b" "):
    padding = (-len(data)) % 4
    if padding:
        data += pad_byte * padding
    return data


def read_glb_chunks(path):
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError("file is too small for a GLB header")
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(data):
        raise ValueError("invalid GLB 2.0 header")
    chunks = []
    offset = 12
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk_data = data[offset:offset + chunk_length]
        offset += chunk_length
        chunks.append((chunk_type, chunk_data))
    return chunks


def write_glb_chunks(path, chunks):
    body = bytearray()
    for chunk_type, chunk_data in chunks:
        body.extend(struct.pack("<II", len(chunk_data), chunk_type))
        body.extend(chunk_data)
    total_length = 12 + len(body)
    with path.open("wb") as file:
        file.write(struct.pack("<4sII", b"glTF", 2, total_length))
        file.write(body)


def repair_blender_vehicle_names(path):
    chunks = read_glb_chunks(path)
    repaired = []
    json_repaired = False
    for chunk_type, chunk_data in chunks:
        if chunk_type != JSON_CHUNK_TYPE or json_repaired:
            repaired.append((chunk_type, chunk_data))
            continue
        gltf = json.loads(chunk_data.rstrip(b" ").decode("utf-8"))
        for node in gltf.get("nodes", []):
            if not isinstance(node, dict):
                continue
            name = str(node.get("name", ""))
            if re.fullmatch(r"wheel_mesh\.\d{3}", name):
                node["name"] = "wheel_mesh"
        json_data = pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
        repaired.append((chunk_type, json_data))
        json_repaired = True
    if not json_repaired:
        raise ValueError("GLB has no JSON chunk to repair")
    write_glb_chunks(path, repaired)


def main():
    args = parse_args()
    if not args.scaffold_glb.is_file():
        print(f"fail: scaffold GLB does not exist: {args.scaffold_glb}", file=sys.stderr)
        return 1
    if not args.donor_glb.is_file():
        print(f"fail: donor GLB does not exist: {args.donor_glb}", file=sys.stderr)
        return 1
    if not args.blender.is_file():
        print(f"fail: Blender binary does not exist: {args.blender}", file=sys.stderr)
        return 1
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as script_file:
        script_file.write(BLENDER_SCRIPT)
        script_path = Path(script_file.name)
    try:
        command = [
            str(args.blender),
            "--background",
            "--python",
            str(script_path),
            "--",
            str(args.scaffold_glb),
            str(args.donor_glb),
            str(args.output_glb),
            "--donor-node-name",
            args.donor_node_name,
            "--donor-largest-dimension",
            f"{args.donor_largest_dimension:.6f}",
            "--donor-bottom-y",
            f"{args.donor_bottom_y:.6f}",
            "--donor-center-z",
            f"{args.donor_center_z:.6f}",
            "--max-donor-triangles",
            str(args.max_donor_triangles),
        ]
        completed = subprocess.run(command, check=False)
        if completed.returncode != 0:
            return completed.returncode
    finally:
        script_path.unlink(missing_ok=True)
    repair_blender_vehicle_names(args.output_glb)
    print(f"wrote: {args.output_glb}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
