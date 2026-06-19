#!/usr/bin/env python3
import math
import warnings
from pathlib import Path

import bpy
from mathutils import Vector


warnings.filterwarnings("ignore", category=DeprecationWarning)

ROOT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT_DIR / "assets" / "models" / "foliage"
GENERATOR_NAME = "Trailhead gen_foliage_glb.py"

COTTONWOOD_OUT = OUT_DIR / "cottonwood.glb"
WILLOW_OUT = OUT_DIR / "willow.glb"
JUNIPER_OUT = OUT_DIR / "juniper.glb"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def try_enable_sapling() -> bool:
    module_names = ("add_curve_sapling", "sapling_tree_gen")
    available_modules: set[str] = set()
    try:
        import addon_utils

        for module in addon_utils.modules():
            available_modules.add(module.__name__)
    except Exception:
        available_modules = set()
    for module_name in module_names:
        if module_name not in available_modules:
            continue
        try:
            bpy.ops.preferences.addon_enable(module=module_name)
        except Exception:
            continue
        if hasattr(bpy.ops.curve, "tree_add"):
            print("Sapling Tree Gen available via " + module_name)
            return True
    print("Sapling Tree Gen unavailable; using deterministic hand-built foliage meshes.")
    return False


def make_material(name: str, color: tuple[float, float, float, float], roughness: float, double_sided: bool) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_backface_culling = not double_sided
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        if "Base Color" in principled.inputs:
            principled.inputs["Base Color"].default_value = color
        if "Metallic" in principled.inputs:
            principled.inputs["Metallic"].default_value = 0.0
        if "Roughness" in principled.inputs:
            principled.inputs["Roughness"].default_value = roughness
        if "Alpha" in principled.inputs:
            principled.inputs["Alpha"].default_value = color[3]
    return material


def select_active(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_object_transform(obj: bpy.types.Object) -> None:
    select_active(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def shade_smooth(obj: bpy.types.Object) -> None:
    select_active(obj)
    bpy.ops.object.shade_smooth()


def add_cone_between(
        name: str,
        start: Vector,
        end: Vector,
        radius_start: float,
        radius_end: float,
        vertices: int,
        material: bpy.types.Material) -> bpy.types.Object:
    direction = end - start
    length = direction.length
    if length <= 0.0001:
        raise ValueError("zero-length branch: " + name)
    midpoint = start + direction * 0.5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_start,
        radius2=radius_end,
        depth=length,
        end_fill_type="TRIFAN",
        location=midpoint,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(material)
    shade_smooth(obj)
    apply_object_transform(obj)
    return obj


def add_leaf_cluster(
        name: str,
        center: Vector,
        scale: Vector,
        rotation: tuple[float, float, float],
        subdivisions: int,
        material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.scale = scale
    obj.rotation_euler = rotation
    obj.data.materials.append(material)
    shade_smooth(obj)
    apply_object_transform(obj)
    return obj


def add_low_poly_leaf_cluster(
        name: str,
        center: Vector,
        scale: Vector,
        rotation: tuple[float, float, float],
        subdivisions: int,
        material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    obj.scale = scale
    obj.rotation_euler = rotation
    obj.data.materials.append(material)
    apply_object_transform(obj)
    return obj


def trunk_center_at(height: float) -> Vector:
    t = min(max(height / 10.2, 0.0), 1.0)
    return Vector((0.22 * t + 0.10 * math.sin(t * math.pi * 0.8), -0.14 * t, height))


def radial(angle_degrees: float) -> Vector:
    radians = math.radians(angle_degrees)
    return Vector((math.cos(radians), math.sin(radians), 0.0))


def add_cottonwood_branches(objects: list[bpy.types.Object], bark: bpy.types.Material) -> list[tuple[Vector, Vector, float]]:
    branch_specs = [
        (2.7, 22.0, 3.1, 1.0, 0.24),
        (3.0, 132.0, 3.6, 0.9, 0.22),
        (3.4, 262.0, 3.4, 0.8, 0.21),
        (4.0, 72.0, 3.8, 1.1, 0.19),
        (4.5, 194.0, 3.5, 1.0, 0.18),
        (5.1, 315.0, 3.0, 1.3, 0.16),
        (5.8, 28.0, 2.8, 1.5, 0.14),
        (6.1, 152.0, 2.6, 1.4, 0.13),
        (6.5, 246.0, 2.4, 1.6, 0.12),
    ]
    branch_ends: list[tuple[Vector, Vector, float]] = []
    for index, spec in enumerate(branch_specs):
        height, angle_degrees, length, rise, radius = spec
        start = trunk_center_at(height)
        direction = radial(angle_degrees)
        end = start + direction * length + Vector((0.0, 0.0, rise))
        objects.append(add_cone_between("cottonwood_primary_" + str(index), start, end, radius, radius * 0.45, 9, bark))
        branch_ends.append((start, end, angle_degrees))
        for side_index, side_offset in enumerate((-38.0, 34.0)):
            secondary_start = start.lerp(end, 0.52 + 0.08 * float(side_index))
            secondary_direction = radial(angle_degrees + side_offset)
            secondary_length = length * (0.36 + 0.06 * float((index + side_index) % 2))
            secondary_rise = 0.42 + 0.13 * float((index + side_index) % 3)
            secondary_end = secondary_start + secondary_direction * secondary_length + Vector((0.0, 0.0, secondary_rise))
            objects.append(add_cone_between(
                "cottonwood_secondary_" + str(index) + "_" + str(side_index),
                secondary_start,
                secondary_end,
                radius * 0.42,
                radius * 0.14,
                7,
                bark,
            ))
            branch_ends.append((secondary_start, secondary_end, angle_degrees + side_offset))
        twig_start = start.lerp(end, 0.72)
        twig_direction = radial(angle_degrees + 72.0)
        twig_end = twig_start + twig_direction * (length * 0.25) + Vector((0.0, 0.0, 0.58))
        objects.append(add_cone_between("cottonwood_twig_" + str(index), twig_start, twig_end, radius * 0.28, radius * 0.08, 6, bark))
        branch_ends.append((twig_start, twig_end, angle_degrees + 72.0))
    return branch_ends


def add_cottonwood_canopy(objects: list[bpy.types.Object], leaves: bpy.types.Material, branch_ends: list[tuple[Vector, Vector, float]]) -> None:
    ring_specs = [
        (4.85, 2.65, 11, 1.00, 0.68),
        (6.25, 3.25, 15, 1.14, 0.78),
        (7.72, 2.72, 13, 1.02, 0.72),
        (8.95, 1.72, 8, 0.82, 0.62),
    ]
    cluster_index = 0
    for ring_index, spec in enumerate(ring_specs):
        height, radius, count, horizontal_scale, vertical_scale = spec
        for i in range(count):
            angle = math.tau * (float(i) / float(count)) + float(ring_index) * 0.31
            wobble = 0.84 + 0.24 * float((i * 7 + ring_index * 5) % 9) / 8.0
            center = Vector((
                math.cos(angle) * radius * wobble + 0.18 * math.sin(angle * 2.0),
                math.sin(angle) * radius * (0.82 + 0.10 * math.cos(angle * 3.0)),
                height + 0.22 * math.sin(angle * 2.3 + float(ring_index)),
            ))
            scale = Vector((
                horizontal_scale * (0.86 + 0.05 * float(i % 5)),
                horizontal_scale * (0.74 + 0.06 * float((i + 2) % 4)),
                vertical_scale * (0.90 + 0.05 * float((i + 1) % 5)),
            ))
            rotation = (0.10 * float((i % 3) - 1), 0.0, angle * 0.18)
            objects.append(add_leaf_cluster("cottonwood_leaf_cluster_" + str(cluster_index), center, scale, rotation, 2, leaves))
            cluster_index += 1
    for branch_index, branch_end in enumerate(branch_ends):
        _start, end, angle_degrees = branch_end
        if branch_index % 3 == 1:
            continue
        center = end + Vector((0.0, 0.0, 0.18))
        scale = Vector((0.58 + 0.06 * float(branch_index % 3), 0.48 + 0.04 * float(branch_index % 4), 0.42))
        objects.append(add_leaf_cluster(
            "cottonwood_terminal_cluster_" + str(branch_index),
            center,
            scale,
            (0.04 * float((branch_index % 5) - 2), 0.0, math.radians(angle_degrees) * 0.2),
            2,
            leaves,
        ))


def build_cottonwood() -> bpy.types.Object:
    clear_scene()
    bark = make_material("cottonwood_bark", (0.42, 0.33, 0.23, 1.0), 0.92, False)
    leaves = make_material("cottonwood_yellow_green_leaves", (0.42, 0.55, 0.26, 1.0), 0.86, True)
    objects: list[bpy.types.Object] = []
    trunk_points = [
        Vector((0.0, 0.0, 0.0)),
        Vector((0.08, -0.03, 2.3)),
        Vector((0.18, -0.10, 4.7)),
        Vector((0.30, -0.16, 6.8)),
    ]
    trunk_radii = [0.34, 0.28, 0.19, 0.08]
    for i in range(len(trunk_points) - 1):
        objects.append(add_cone_between(
            "cottonwood_trunk_" + str(i),
            trunk_points[i],
            trunk_points[i + 1],
            trunk_radii[i],
            trunk_radii[i + 1],
            10,
            bark,
        ))
    branch_ends = add_cottonwood_branches(objects, bark)
    add_cottonwood_canopy(objects, leaves, branch_ends)
    return join_tree_objects("cottonwood", objects, bark, leaves)


def willow_stem_end(index: int, count: int) -> tuple[Vector, Vector, Vector]:
    angle = math.tau * float(index) / float(count)
    base_radius = 0.10 + 0.10 * float(index % 3) / 2.0
    base = Vector((math.cos(angle) * base_radius, math.sin(angle) * base_radius, 0.0))
    arc = 0.82 + 0.18 * float((index * 5) % 7) / 6.0
    height = 4.0 + 0.78 * float((index * 3) % 9) / 8.0
    mid = base + radial(math.degrees(angle) + 8.0 * math.sin(float(index))) * (0.58 * arc) + Vector((0.0, 0.0, height * 0.50))
    end = base + radial(math.degrees(angle) + 18.0 * math.cos(float(index) * 0.7)) * (1.35 * arc) + Vector((0.0, 0.0, height))
    return base, mid, end


def build_willow() -> bpy.types.Object:
    clear_scene()
    bark = make_material("willow_bark", (0.30, 0.22, 0.13, 1.0), 0.94, False)
    leaves = make_material("willow_silvery_green_leaves", (0.46, 0.54, 0.34, 1.0), 0.88, True)
    objects: list[bpy.types.Object] = []
    stem_count = 13
    cluster_index = 0
    for i in range(stem_count):
        base, mid, end = willow_stem_end(i, stem_count)
        radius = 0.070 + 0.010 * float(i % 3)
        objects.append(add_cone_between("willow_stem_lower_" + str(i), base, mid, radius, radius * 0.56, 7, bark))
        objects.append(add_cone_between("willow_stem_upper_" + str(i), mid, end, radius * 0.56, radius * 0.18, 6, bark))
        for side_index, side_offset in enumerate((-28.0, 24.0, 52.0)):
            side_start = mid.lerp(end, 0.35 + 0.16 * float(side_index))
            angle = math.degrees(math.atan2(end.y - base.y, end.x - base.x)) + side_offset
            side_end = side_start + radial(angle) * (0.55 + 0.10 * float((i + side_index) % 4)) + Vector((0.0, 0.0, 0.30 - 0.08 * float(side_index)))
            objects.append(add_cone_between(
                "willow_side_branch_" + str(i) + "_" + str(side_index),
                side_start,
                side_end,
                radius * 0.28,
                radius * 0.08,
                5,
                bark,
            ))
            cluster_center = side_end + Vector((0.0, 0.0, -0.08 * float(side_index)))
            cluster_scale = Vector((0.42 + 0.05 * float(side_index), 0.24 + 0.03 * float(i % 3), 0.62 + 0.07 * float((i + side_index) % 4)))
            objects.append(add_leaf_cluster(
                "willow_leaf_cluster_" + str(cluster_index),
                cluster_center,
                cluster_scale,
                (0.12 * float(side_index), 0.04 * float((i % 3) - 1), math.radians(angle) * 0.25),
                1,
                leaves,
            ))
            cluster_index += 1
        top_scale = Vector((0.50 + 0.06 * float(i % 4), 0.30, 0.70 + 0.05 * float(i % 5)))
        objects.append(add_leaf_cluster(
            "willow_top_cluster_" + str(i),
            end + Vector((0.0, 0.0, -0.16)),
            top_scale,
            (0.18, 0.0, angle * 0.12),
            1,
            leaves,
        ))
        cluster_index += 1
    return join_tree_objects("willow", objects, bark, leaves)


def juniper_trunk_center_at(height: float) -> Vector:
    t = min(max(height / 1.52, 0.0), 1.0)
    return Vector((
        0.10 * math.sin(t * math.pi * 1.65) + 0.13 * t,
        -0.08 * math.sin(t * math.pi * 0.95),
        height,
    ))


def add_juniper_branches(objects: list[bpy.types.Object], bark: bpy.types.Material) -> list[Vector]:
    branch_specs = [
        (0.45, 22.0, 0.88, 0.38, 0.105),
        (0.55, 142.0, 0.76, 0.45, 0.095),
        (0.70, 246.0, 0.86, 0.36, 0.088),
        (0.92, 76.0, 1.06, 0.66, 0.080),
        (1.05, 188.0, 0.96, 0.58, 0.074),
        (1.22, 314.0, 0.82, 0.70, 0.066),
        (1.38, 34.0, 0.56, 0.94, 0.058),
    ]
    branch_ends: list[Vector] = []
    for index, spec in enumerate(branch_specs):
        height, angle_degrees, length, rise, radius = spec
        start = juniper_trunk_center_at(height)
        direction = radial(angle_degrees)
        bend = start + radial(angle_degrees + 18.0 * math.sin(float(index) * 1.3)) * (length * 0.48) + Vector((0.0, 0.0, rise * 0.40))
        end = start + direction * length + Vector((0.0, 0.0, rise))
        objects.append(add_cone_between("juniper_branch_lower_" + str(index), start, bend, radius, radius * 0.66, 7, bark))
        objects.append(add_cone_between("juniper_branch_upper_" + str(index), bend, end, radius * 0.66, radius * 0.18, 6, bark))
        branch_ends.append(end)
        if index % 2 == 0:
            fork_direction = radial(angle_degrees + 42.0 + 8.0 * float(index % 3))
            fork_end = bend + fork_direction * (length * 0.42) + Vector((0.0, 0.0, rise * 0.32))
            objects.append(add_cone_between(
                "juniper_branch_fork_" + str(index),
                bend,
                fork_end,
                radius * 0.40,
                radius * 0.12,
                5,
                bark,
            ))
            branch_ends.append(fork_end)
    return branch_ends


def add_juniper_canopy(objects: list[bpy.types.Object], leaves: bpy.types.Material, branch_ends: list[Vector]) -> None:
    ring_specs = [
        (1.12, 0.92, 6, 0.48, 0.36),
        (1.58, 1.24, 8, 0.58, 0.44),
        (2.02, 1.02, 7, 0.56, 0.44),
        (2.48, 0.62, 4, 0.48, 0.40),
        (2.92, 0.18, 1, 0.40, 0.34),
    ]
    cluster_index = 0
    for ring_index, spec in enumerate(ring_specs):
        height, radius, count, horizontal_scale, vertical_scale = spec
        for i in range(count):
            angle = math.tau * (float(i) / float(count)) + float(ring_index) * 0.41
            wobble = 0.78 + 0.30 * float((i * 5 + ring_index * 7) % 11) / 10.0
            center = Vector((
                math.cos(angle) * radius * wobble + 0.10 * math.sin(angle * 2.7),
                math.sin(angle) * radius * (0.84 + 0.12 * math.cos(angle * 1.9)),
                height + 0.13 * math.sin(angle * 2.1 + float(ring_index)),
            ))
            scale = Vector((
                horizontal_scale * (0.86 + 0.08 * float((i + ring_index) % 4)),
                horizontal_scale * (0.74 + 0.07 * float((i * 3 + ring_index) % 5)),
                vertical_scale * (0.90 + 0.06 * float((i + 2) % 4)),
            ))
            rotation = (
                0.10 * float((i % 3) - 1),
                0.07 * float(((i + ring_index) % 3) - 1),
                angle * 0.22,
            )
            objects.append(add_low_poly_leaf_cluster("juniper_leaf_cluster_" + str(cluster_index), center, scale, rotation, 2, leaves))
            cluster_index += 1
    for branch_index, end in enumerate(branch_ends):
        if branch_index % 2 == 1:
            continue
        scale = Vector((0.36 + 0.04 * float(branch_index % 3), 0.30, 0.28 + 0.04 * float(branch_index % 2)))
        objects.append(add_low_poly_leaf_cluster(
            "juniper_terminal_cluster_" + str(branch_index),
            end + Vector((0.0, 0.0, 0.05)),
            scale,
            (0.06 * float((branch_index % 5) - 2), 0.0, float(branch_index) * 0.19),
            1,
            leaves,
        ))


def build_juniper() -> bpy.types.Object:
    clear_scene()
    bark = make_material("juniper_shaggy_bark", (0.32, 0.26, 0.18, 1.0), 0.96, False)
    leaves = make_material("juniper_blue_green_leaves", (0.24, 0.34, 0.24, 1.0), 0.90, True)
    objects: list[bpy.types.Object] = []
    trunk_points = [
        Vector((0.0, 0.0, 0.0)),
        Vector((0.10, -0.05, 0.48)),
        Vector((-0.04, 0.02, 0.94)),
        Vector((0.13, -0.08, 1.52)),
    ]
    trunk_radii = [0.20, 0.18, 0.13, 0.070]
    for i in range(len(trunk_points) - 1):
        objects.append(add_cone_between(
            "juniper_twisted_trunk_" + str(i),
            trunk_points[i],
            trunk_points[i + 1],
            trunk_radii[i],
            trunk_radii[i + 1],
            8,
            bark,
        ))
    branch_ends = add_juniper_branches(objects, bark)
    add_juniper_canopy(objects, leaves, branch_ends)
    return join_tree_objects("juniper", objects, bark, leaves)


def join_tree_objects(name: str, objects: list[bpy.types.Object], bark: bpy.types.Material, leaves: bpy.types.Material) -> bpy.types.Object:
    if not objects:
        raise ValueError("no objects built for " + name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_mesh"
    normalize_material_slots(obj, bark, leaves)
    select_active(obj)
    bpy.ops.object.modifier_add(type="TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier="Triangulate")
    obj["generator"] = GENERATOR_NAME
    obj["triangle_count"] = triangle_count(obj)
    return obj


def normalize_material_slots(obj: bpy.types.Object, bark: bpy.types.Material, leaves: bpy.types.Material) -> None:
    old_names: list[str] = []
    for slot_material in obj.data.materials:
        old_names.append(slot_material.name.lower() if slot_material is not None else "")
    material_indices: list[int] = []
    for polygon in obj.data.polygons:
        old_name = ""
        if polygon.material_index >= 0 and polygon.material_index < len(old_names):
            old_name = old_names[polygon.material_index]
        material_indices.append(1 if "leaves" in old_name or "leaf" in old_name else 0)
    obj.data.materials.clear()
    obj.data.materials.append(bark)
    obj.data.materials.append(leaves)
    for polygon_index, polygon in enumerate(obj.data.polygons):
        polygon.material_index = material_indices[polygon_index]


def triangle_count(obj: bpy.types.Object) -> int:
    total = 0
    for polygon in obj.data.polygons:
        total += max(len(polygon.vertices) - 2, 1)
    return total


def dimensions_y_up_from_blender(obj: bpy.types.Object) -> tuple[float, float, float]:
    min_x = min((obj.matrix_world @ Vector(corner)).x for corner in obj.bound_box)
    max_x = max((obj.matrix_world @ Vector(corner)).x for corner in obj.bound_box)
    min_y = min((obj.matrix_world @ Vector(corner)).y for corner in obj.bound_box)
    max_y = max((obj.matrix_world @ Vector(corner)).y for corner in obj.bound_box)
    min_z = min((obj.matrix_world @ Vector(corner)).z for corner in obj.bound_box)
    max_z = max((obj.matrix_world @ Vector(corner)).z for corner in obj.bound_box)
    return max_x - min_x, max_z - min_z, max_y - min_y


def export_tree(obj: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    select_active(obj)
    kwargs = {
        "filepath": str(path),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_materials": "EXPORT",
        "export_yup": True,
    }
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_yup", None)
        bpy.ops.export_scene.gltf(**kwargs)
    tris = triangle_count(obj)
    width, height, depth = dimensions_y_up_from_blender(obj)
    print(name_report(obj.name, path, tris, width, height, depth))


def name_report(name: str, path: Path, tris: int, width: float, height: float, depth: float) -> str:
    return (
        "exported "
        + name
        + " to "
        + str(path)
        + " tris="
        + str(tris)
        + " size_m=("
        + format(width, ".2f")
        + ", "
        + format(height, ".2f")
        + ", "
        + format(depth, ".2f")
        + ")"
    )


def main() -> None:
    try_enable_sapling()
    cottonwood = build_cottonwood()
    export_tree(cottonwood, COTTONWOOD_OUT)
    willow = build_willow()
    export_tree(willow, WILLOW_OUT)
    juniper = build_juniper()
    export_tree(juniper, JUNIPER_OUT)


if __name__ == "__main__":
    main()
