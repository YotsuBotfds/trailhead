#!/usr/bin/env python3
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_BLENDER = Path("/Applications/Blender.app/Contents/MacOS/Blender")

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
    parser = argparse.ArgumentParser(description="Clean a Trellis2 GLB inside Blender.")
    parser.add_argument("input_glb")
    parser.add_argument("output_glb")
    parser.add_argument("--asset-name", required=True)
    parser.add_argument("--target-largest-dimension", type=float, required=True)
    parser.add_argument("--max-triangles", type=int, default=180000)
    return parser.parse_args(argv)


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


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_meshes(path):
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("import produced no mesh objects")
    for obj in meshes:
        world_matrix = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world_matrix
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    if len(meshes) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
        meshes = [bpy.context.object]
    return meshes[0]


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


def triangle_count(obj):
    return sum(max(len(poly.vertices) - 2, 0) for poly in obj.data.polygons)


def decimate_if_needed(obj, max_triangles):
    current_triangles = triangle_count(obj)
    if max_triangles <= 0 or current_triangles <= max_triangles:
        return
    ratio = max(0.01, float(max_triangles) / float(current_triangles))
    modifier = obj.modifiers.new("manifest_decimate", "DECIMATE")
    modifier.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def normalize_object(obj, asset_name, target_largest_dimension):
    obj.name = asset_name
    obj.data.name = asset_name
    bpy.context.view_layer.update()
    bounds_min, bounds_max = bounds_for([obj])
    dimensions = bounds_max - bounds_min
    largest = max(dimensions.x, dimensions.y, dimensions.z)
    if largest <= 0.000001:
        raise RuntimeError("imported mesh has degenerate bounds")
    scale_factor = target_largest_dimension / largest
    obj.scale = obj.scale * scale_factor
    bpy.context.view_layer.update()
    bounds_min, bounds_max = bounds_for([obj])
    center_x = (bounds_min.x + bounds_max.x) * 0.5
    center_y = (bounds_min.y + bounds_max.y) * 0.5
    obj.location.x -= center_x
    obj.location.y -= center_y
    obj.location.z -= bounds_min.z
    bpy.context.view_layer.update()


def export_glb(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_image_format="JPEG",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
    )


def main():
    args = parse_blender_args()
    clear_scene()
    mesh = import_meshes(Path(args.input_glb))
    decimate_if_needed(mesh, args.max_triangles)
    add_uv_if_missing(mesh)
    normalize_object(mesh, args.asset_name, args.target_largest_dimension)
    export_glb(Path(args.output_glb))


main()
'''


def parse_args():
    parser = argparse.ArgumentParser(description="Clean a raw Trellis2 GLB through Blender for Trailhead intake.")
    parser.add_argument("input_glb", type=Path)
    parser.add_argument("output_glb", type=Path)
    parser.add_argument("--asset-name", required=True)
    parser.add_argument("--target-largest-dimension", type=float, required=True)
    parser.add_argument("--max-triangles", type=int, default=180000)
    parser.add_argument("--blender", type=Path, default=DEFAULT_BLENDER)
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.input_glb.is_file():
        print(f"fail: input GLB does not exist: {args.input_glb}", file=sys.stderr)
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
            str(args.input_glb),
            str(args.output_glb),
            "--asset-name",
            args.asset_name,
            "--target-largest-dimension",
            f"{args.target_largest_dimension:.6f}",
            "--max-triangles",
            str(args.max_triangles),
        ]
        completed = subprocess.run(command, check=False)
        if completed.returncode != 0:
            return completed.returncode
    finally:
        script_path.unlink(missing_ok=True)
    print(f"wrote: {args.output_glb}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
