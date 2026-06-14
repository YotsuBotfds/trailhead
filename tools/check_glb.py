#!/usr/bin/env python3
import argparse
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path

JSON_CHUNK_TYPE = 0x4E4F534A
TRIANGLES = 4
TRIANGLE_STRIP = 5
TRIANGLE_FAN = 6
SURFACE_PATTERN = re.compile(r"__surf_([A-Za-z0-9_]+)")
WHEEL_PATTERN = re.compile(r"(wheel|tire|tyre)", re.IGNORECASE)
SNAKE_CASE_PATTERN = re.compile(r"^[a-z0-9_]+$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
VEHICLE_WHEEL_SOCKET_POSITIONS = {
    "wheel_front_left": [-0.08, -0.015, -0.10],
    "wheel_front_right": [0.08, -0.015, -0.10],
    "wheel_rear_left": [-0.08, -0.015, 0.10],
    "wheel_rear_right": [0.08, -0.015, 0.10],
}
VEHICLE_SOCKET_TOLERANCE = 0.001
DECORATION_PROFILE_DEFAULTS = {
    "prop": {
        "min_dimension": 0.05,
        "max_dimension": 4.0,
    },
    "scatter": {
        "min_dimension": 0.05,
        "max_dimension": 1.5,
    },
}
RENDER_ATTRIBUTE_SET = {"POSITION", "NORMAL", "TEXCOORD_0"}


def fail(message):
    print(f"fail: {message}")
    return False


def read_glb(path):
    data = path.read_bytes()
    if len(data) < 12:
        raise ValueError("file is too small for a GLB header")
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("missing glTF magic")
    if version != 2:
        raise ValueError(f"unsupported GLB version {version}")
    if declared_length != len(data):
        raise ValueError(f"declared length {declared_length} != actual length {len(data)}")

    offset = 12
    json_chunk = None
    bin_chunk_count = 0
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk_data = data[offset:offset + chunk_length]
        offset += chunk_length
        if chunk_type == JSON_CHUNK_TYPE:
            json_chunk = chunk_data
        elif chunk_type == 0x004E4942:
            bin_chunk_count += 1
    if json_chunk is None:
        raise ValueError("missing JSON chunk")
    return json.loads(json_chunk.decode("utf-8").rstrip(" \t\r\n\0")), bin_chunk_count


def read_png_summary(path):
	data = path.read_bytes()
	if len(data) < 24:
		raise ValueError("surface-ID map is too small for a PNG header")
	if data[:8] != PNG_SIGNATURE:
		raise ValueError("surface-ID map is not a PNG")
	offset = 8
	width = 0
	height = 0
	bit_depth = 0
	color_type = 0
	idat_chunks = []
	while offset + 8 <= len(data):
		chunk_length = struct.unpack_from(">I", data, offset)[0]
		offset += 4
		chunk_type = data[offset:offset + 4]
		offset += 4
		chunk_data = data[offset:offset + chunk_length]
		offset += chunk_length + 4
		if chunk_type == b"IHDR":
			width, height, bit_depth, color_type, _compression, _filter, interlace = struct.unpack_from(">IIBBBBB", chunk_data, 0)
			if interlace != 0:
				raise ValueError("surface-ID map must be non-interlaced")
		elif chunk_type == b"IDAT":
			idat_chunks.append(chunk_data)
		elif chunk_type == b"IEND":
			break
	if width <= 0 or height <= 0:
		raise ValueError(f"surface-ID map has invalid dimensions {width}x{height}")
	if bit_depth != 8:
		raise ValueError(f"surface-ID map must use 8-bit channels, got bit depth {bit_depth}")
	samples = decode_png_samples(width, height, color_type, b"".join(idat_chunks))
	return {
		"width": width,
		"height": height,
		"bit_depth": bit_depth,
		"color_type": color_type,
		"unique_samples": sorted(set(samples)),
	}


def decode_png_samples(width, height, color_type, compressed_data):
	channels_by_color_type = {
		0: 1,
		2: 3,
		3: 1,
		4: 2,
		6: 4,
	}
	channels = channels_by_color_type.get(color_type)
	if channels is None:
		raise ValueError(f"unsupported surface-ID map color type {color_type}")
	stride = width * channels
	raw = zlib.decompress(compressed_data)
	expected_size = (stride + 1) * height
	if len(raw) != expected_size:
		raise ValueError(f"surface-ID map payload size {len(raw)} != expected {expected_size}")
	rows = []
	previous = bytearray(stride)
	offset = 0
	for _y in range(height):
		filter_type = raw[offset]
		offset += 1
		row = bytearray(raw[offset:offset + stride])
		offset += stride
		unfilter_png_row(row, previous, channels, filter_type)
		rows.append(bytes(row))
		previous = row
	samples = []
	for row in rows:
		for x in range(width):
			samples.append(row[x * channels])
	return samples


def unfilter_png_row(row, previous, bytes_per_pixel, filter_type):
	if filter_type == 0:
		return
	if filter_type == 1:
		for index in range(len(row)):
			left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + left) & 0xFF
		return
	if filter_type == 2:
		for index in range(len(row)):
			row[index] = (row[index] + previous[index]) & 0xFF
		return
	if filter_type == 3:
		for index in range(len(row)):
			left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			up = previous[index]
			row[index] = (row[index] + ((left + up) // 2)) & 0xFF
		return
	if filter_type == 4:
		for index in range(len(row)):
			left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			up = previous[index]
			up_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + paeth(left, up, up_left)) & 0xFF
		return
	raise ValueError(f"unsupported PNG filter type {filter_type}")


def paeth(left, up, up_left):
	p = left + up - up_left
	pa = abs(p - left)
	pb = abs(p - up)
	pc = abs(p - up_left)
	if pa <= pb and pa <= pc:
		return left
	if pb <= pc:
		return up
	return up_left


def accessor_count(gltf, accessor_index):
    accessors = gltf.get("accessors", [])
    if accessor_index is None or accessor_index < 0 or accessor_index >= len(accessors):
        return 0
    return int(accessors[accessor_index].get("count", 0))


def primitive_position_accessor(primitive):
    attributes = primitive.get("attributes", {})
    value = attributes.get("POSITION")
    if isinstance(value, int):
        return value
    return None


def primitive_triangle_count(gltf, primitive):
    mode = int(primitive.get("mode", TRIANGLES))
    index_accessor = primitive.get("indices")
    position_accessor = primitive_position_accessor(primitive)
    count = accessor_count(gltf, index_accessor if isinstance(index_accessor, int) else position_accessor)
    if mode == TRIANGLES:
        return count // 3
    if mode == TRIANGLE_STRIP or mode == TRIANGLE_FAN:
        return max(0, count - 2)
    return 0


def vector_from_property(value, length, default):
    if not isinstance(value, list) or len(value) < length:
        return list(default)
    try:
        return [float(value[index]) for index in range(length)]
    except (TypeError, ValueError):
        return list(default)


def identity_matrix():
    return [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def translation_matrix(translation):
    matrix = identity_matrix()
    matrix[0][3] = translation[0]
    matrix[1][3] = translation[1]
    matrix[2][3] = translation[2]
    return matrix


def scale_matrix(scale):
    matrix = identity_matrix()
    matrix[0][0] = scale[0]
    matrix[1][1] = scale[1]
    matrix[2][2] = scale[2]
    return matrix


def rotation_matrix(rotation):
    x, y, z, w = rotation
    length = math.sqrt(x * x + y * y + z * z + w * w)
    if length <= 0.0:
        return identity_matrix()
    x /= length
    y /= length
    z /= length
    w /= length
    xx = x * x
    yy = y * y
    zz = z * z
    xy = x * y
    xz = x * z
    yz = y * z
    wx = w * x
    wy = w * y
    wz = w * z
    return [
        [1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz), 2.0 * (xz + wy), 0.0],
        [2.0 * (xy + wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx), 0.0],
        [2.0 * (xz - wy), 2.0 * (yz + wx), 1.0 - 2.0 * (xx + yy), 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]


def matrix_multiply(a, b):
    result = []
    for row in range(4):
        result_row = []
        for column in range(4):
            result_row.append(sum(a[row][index] * b[index][column] for index in range(4)))
        result.append(result_row)
    return result


def transform_point(matrix, point):
    x, y, z = point
    w = matrix[3][0] * x + matrix[3][1] * y + matrix[3][2] * z + matrix[3][3]
    if abs(w) <= 0.000001:
        w = 1.0
    return [
        (matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z + matrix[0][3]) / w,
        (matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z + matrix[1][3]) / w,
        (matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z + matrix[2][3]) / w,
    ]


def node_matrix_values(node):
    matrix = node.get("matrix")
    if not isinstance(matrix, list) or len(matrix) < 16:
        return None
    try:
        return [float(matrix[index]) for index in range(16)]
    except (TypeError, ValueError):
        return None


def node_translation(node):
    matrix = node_matrix_values(node)
    if matrix is not None:
        return [matrix[12], matrix[13], matrix[14]]
    return vector_from_property(node.get("translation"), 3, [0.0, 0.0, 0.0])


def node_local_matrix(node):
    values = node_matrix_values(node)
    if values is not None:
        return [
            [values[0], values[4], values[8], values[12]],
            [values[1], values[5], values[9], values[13]],
            [values[2], values[6], values[10], values[14]],
            [values[3], values[7], values[11], values[15]],
        ]
    translation = vector_from_property(node.get("translation"), 3, [0.0, 0.0, 0.0])
    rotation = vector_from_property(node.get("rotation"), 4, [0.0, 0.0, 0.0, 1.0])
    scale = vector_from_property(node.get("scale"), 3, [1.0, 1.0, 1.0])
    return matrix_multiply(translation_matrix(translation), matrix_multiply(rotation_matrix(rotation), scale_matrix(scale)))


def accessor_bounds_for_primitive(gltf, primitive):
    accessors = gltf.get("accessors", [])
    position_accessor = primitive_position_accessor(primitive)
    if position_accessor is None or position_accessor < 0 or position_accessor >= len(accessors):
        return None
    accessor = accessors[position_accessor]
    amin = accessor.get("min")
    amax = accessor.get("max")
    if not isinstance(amin, list) or not isinstance(amax, list) or len(amin) < 3 or len(amax) < 3:
        return None
    try:
        return [float(amin[index]) for index in range(3)], [float(amax[index]) for index in range(3)]
    except (TypeError, ValueError):
        return None


def bounds_corners(bounds_pair):
    bounds_min, bounds_max = bounds_pair
    return [
        [x, y, z]
        for x in (bounds_min[0], bounds_max[0])
        for y in (bounds_min[1], bounds_max[1])
        for z in (bounds_min[2], bounds_max[2])
    ]


def expand_bounds_with_point(bounds_min, bounds_max, point):
    for index in range(3):
        bounds_min[index] = min(bounds_min[index], point[index])
        bounds_max[index] = max(bounds_max[index], point[index])


def scene_root_indices(gltf, nodes):
    scenes = gltf.get("scenes", [])
    scene_index = gltf.get("scene")
    if isinstance(scene_index, int) and 0 <= scene_index < len(scenes):
        roots = scenes[scene_index].get("nodes", [])
        if isinstance(roots, list):
            return [index for index in roots if isinstance(index, int) and 0 <= index < len(nodes)]
    child_indices = set()
    for node in nodes:
        children = node.get("children", [])
        if isinstance(children, list):
            child_indices.update(index for index in children if isinstance(index, int) and 0 <= index < len(nodes))
    return [index for index in range(len(nodes)) if index not in child_indices]


def collect_stats(gltf):
    meshes = gltf.get("meshes", [])
    nodes = gltf.get("nodes", [])
    triangle_count = 0
    primitive_count = 0
    primitive_attributes = []
    mesh_bounds = []
    local_bounds_min = [float("inf"), float("inf"), float("inf")]
    local_bounds_max = [float("-inf"), float("-inf"), float("-inf")]
    has_local_bounds = False

    for mesh in meshes:
        mesh_bounds_min = [float("inf"), float("inf"), float("inf")]
        mesh_bounds_max = [float("-inf"), float("-inf"), float("-inf")]
        has_mesh_bounds = False
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            attributes = primitive.get("attributes", {})
            if isinstance(attributes, dict):
                primitive_attributes.append(sorted(attributes.keys()))
            else:
                primitive_attributes.append([])
            triangle_count += primitive_triangle_count(gltf, primitive)
            bounds_pair = accessor_bounds_for_primitive(gltf, primitive)
            if bounds_pair is not None:
                has_mesh_bounds = True
                has_local_bounds = True
                for corner in bounds_corners(bounds_pair):
                    expand_bounds_with_point(mesh_bounds_min, mesh_bounds_max, corner)
                    expand_bounds_with_point(local_bounds_min, local_bounds_max, corner)
        mesh_bounds.append((mesh_bounds_min, mesh_bounds_max) if has_mesh_bounds else None)

    world_bounds_min = [float("inf"), float("inf"), float("inf")]
    world_bounds_max = [float("-inf"), float("-inf"), float("-inf")]
    has_world_bounds = False

    def visit_node(node_index, parent_matrix, active_nodes):
        nonlocal has_world_bounds
        if node_index in active_nodes or node_index < 0 or node_index >= len(nodes):
            return
        node = nodes[node_index]
        world_matrix = matrix_multiply(parent_matrix, node_local_matrix(node))
        mesh_index = node.get("mesh")
        if isinstance(mesh_index, int) and 0 <= mesh_index < len(mesh_bounds) and mesh_bounds[mesh_index] is not None:
            for corner in bounds_corners(mesh_bounds[mesh_index]):
                expand_bounds_with_point(world_bounds_min, world_bounds_max, transform_point(world_matrix, corner))
            has_world_bounds = True
        children = node.get("children", [])
        if isinstance(children, list):
            next_active_nodes = set(active_nodes)
            next_active_nodes.add(node_index)
            for child_index in children:
                if isinstance(child_index, int):
                    visit_node(child_index, world_matrix, next_active_nodes)

    roots = scene_root_indices(gltf, nodes)
    if not roots and nodes:
        roots = list(range(len(nodes)))
    for root_index in roots:
        visit_node(root_index, identity_matrix(), set())

    if has_world_bounds:
        bounds_min = world_bounds_min
        bounds_max = world_bounds_max
        dimensions = [bounds_max[index] - bounds_min[index] for index in range(3)]
        bounds_source = "world"
    elif has_local_bounds:
        bounds_min = local_bounds_min
        bounds_max = local_bounds_max
        dimensions = [bounds_max[index] - bounds_min[index] for index in range(3)]
        bounds_source = "local"
    else:
        bounds_min = []
        bounds_max = []
        dimensions = []
        bounds_source = "none"

    names = []
    node_summaries = []
    for index, node in enumerate(nodes):
        node_name = str(node.get("name", ""))
        children = node.get("children", [])
        mesh_index = node.get("mesh")
        node_summaries.append({
            "index": index,
            "name": node_name,
            "translation": node_translation(node),
            "children": children if isinstance(children, list) else [],
            "mesh": mesh_index if isinstance(mesh_index, int) else None,
        })
        if "name" in node:
            names.append(node_name)
    for mesh in meshes:
        if "name" in mesh:
            names.append(str(mesh["name"]))

    return {
        "mesh_count": len(meshes),
        "node_count": len(nodes),
        "primitive_count": primitive_count,
        "triangle_count": triangle_count,
        "bounds_min": bounds_min,
        "bounds_max": bounds_max,
        "dimensions": dimensions,
        "local_bounds_min": local_bounds_min if has_local_bounds else [],
        "local_bounds_max": local_bounds_max if has_local_bounds else [],
        "local_dimensions": [local_bounds_max[index] - local_bounds_min[index] for index in range(3)] if has_local_bounds else [],
        "world_bounds_min": world_bounds_min if has_world_bounds else [],
        "world_bounds_max": world_bounds_max if has_world_bounds else [],
        "world_dimensions": [world_bounds_max[index] - world_bounds_min[index] for index in range(3)] if has_world_bounds else [],
        "bounds_source": bounds_source,
        "names": names,
        "nodes": node_summaries,
        "primitive_attributes": primitive_attributes,
    }


def validate_vehicle(stats):
    ok = True
    root_nodes = [node for node in stats["nodes"] if node["name"] == "rc_buggy"]
    if len(root_nodes) != 1:
        ok = fail(f"vehicle profile requires exactly one rc_buggy root node; found {len(root_nodes)}") and ok
        root_children = set()
    else:
        root_children = set(root_nodes[0]["children"])
    for socket_name, expected_position in VEHICLE_WHEEL_SOCKET_POSITIONS.items():
        matching_nodes = [node for node in stats["nodes"] if node["name"] == socket_name]
        if len(matching_nodes) != 1:
            ok = fail(f"vehicle profile requires exactly one {socket_name} node; found {len(matching_nodes)}") and ok
            continue
        socket_node = matching_nodes[0]
        if socket_node["index"] not in root_children:
            ok = fail(f"{socket_name} should be a direct child of rc_buggy") and ok
        translation = matching_nodes[0]["translation"]
        if len(translation) < 3:
            ok = fail(f"{socket_name} translation should have 3 components") and ok
            continue
        for axis in range(3):
            delta = abs(float(translation[axis]) - expected_position[axis])
            if delta > VEHICLE_SOCKET_TOLERANCE:
                ok = fail(f"{socket_name} translation expected {expected_position}, got {translation}") and ok
                break
        child_nodes = [node for node in stats["nodes"] if node["index"] in set(socket_node["children"])]
        mesh_children = [node for node in child_nodes if node["mesh"] is not None]
        if not mesh_children:
            ok = fail(f"{socket_name} should own at least one direct mesh child for wheel animation") and ok
    return ok


def validate_heightmesh(args, stats):
    ok = True
    if stats["mesh_count"] <= 0:
        ok = fail("heightmesh profile requires at least one mesh") and ok
    if stats["primitive_count"] <= 0:
        ok = fail("heightmesh profile requires at least one primitive") and ok
    if stats["triangle_count"] <= 0:
        ok = fail("heightmesh profile requires nonzero triangles") and ok
    if not stats["dimensions"]:
        ok = fail("heightmesh profile requires POSITION min/max bounds") and ok
    else:
        x_size, y_size, z_size = stats["dimensions"][:3]
        if x_size < 6.0 or x_size > 40.0:
            ok = fail(f"heightmesh X extent {x_size:.3f} m is outside expected 6..40 m range") and ok
        if z_size < 6.0 or z_size > 40.0:
            ok = fail(f"heightmesh Z extent {z_size:.3f} m is outside expected 6..40 m range") and ok
        if y_size > 6.0:
            ok = fail(f"heightmesh Y extent {y_size:.3f} m exceeds 6 m vertical sanity limit") and ok

    if not any("cedar_hollow_heightmesh" in name for name in stats["names"]):
        ok = fail("heightmesh profile requires a node or mesh named cedar_hollow_heightmesh") and ok
    for name in stats["names"]:
        if not SNAKE_CASE_PATTERN.match(name):
            ok = fail(f"heightmesh node/mesh name is not snake_case: {name}") and ok

    required_attributes = {"POSITION", "NORMAL", "TEXCOORD_0"}
    for index, attributes in enumerate(stats["primitive_attributes"]):
        missing = sorted(required_attributes.difference(attributes))
        if missing:
            ok = fail(f"heightmesh primitive {index} is missing attributes: {', '.join(missing)}") and ok

    if args.surface_id_map is None:
        ok = fail("heightmesh profile requires --surface-id-map") and ok
    elif not args.surface_id_map.is_file():
        ok = fail(f"surface-ID map not found: {args.surface_id_map}") and ok
    else:
        try:
            png_summary = read_png_summary(args.surface_id_map)
            unique_samples = png_summary["unique_samples"]
            print(f"surface-ID map: {args.surface_id_map} ({png_summary['width']}x{png_summary['height']})")
            print(f"surface-ID map ids: {', '.join(str(value) for value in unique_samples)}")
            if len(unique_samples) < 2:
                ok = fail("surface-ID map must contain at least two distinct IDs") and ok
        except Exception as exc:
            ok = fail(str(exc)) and ok
    return ok


def validate_decoration_profile(args, stats, profile_name, surface_tags, wheel_names):
    ok = True
    expected_name = args.expected_name if args.expected_name is not None else args.path.stem
    defaults = DECORATION_PROFILE_DEFAULTS[profile_name]
    min_dimension = args.min_dimension if args.min_dimension is not None else defaults["min_dimension"]
    max_dimension = args.max_dimension if args.max_dimension is not None else defaults["max_dimension"]

    if stats["mesh_count"] <= 0:
        ok = fail(f"{profile_name} profile requires at least one mesh") and ok
    if stats["primitive_count"] <= 0:
        ok = fail(f"{profile_name} profile requires at least one primitive") and ok
    if stats["triangle_count"] <= 0:
        ok = fail(f"{profile_name} profile requires nonzero triangles") and ok
    if expected_name not in stats["names"]:
        ok = fail(f"{profile_name} profile requires a node or mesh named {expected_name}") and ok
    for name in stats["names"]:
        if not SNAKE_CASE_PATTERN.match(name):
            ok = fail(f"{profile_name} node/mesh name is not snake_case: {name}") and ok
    if surface_tags:
        ok = fail(f"{profile_name} profile is decorative; unexpected surface tags: {', '.join(sorted(set(surface_tags)))}") and ok
    if wheel_names:
        ok = fail(f"{profile_name} profile should not include wheel/tire nodes: {', '.join(wheel_names)}") and ok
    if stats["dimensions"]:
        largest = max(stats["dimensions"])
        if largest < min_dimension:
            ok = fail(f"{profile_name} largest dimension {largest:.3f} m is below min {min_dimension:.3f} m") and ok
        if largest > max_dimension:
            ok = fail(f"{profile_name} largest dimension {largest:.3f} m exceeds max {max_dimension:.3f} m") and ok
    return ok


def validate_render_attributes(stats, label):
    ok = True
    for index, attributes in enumerate(stats["primitive_attributes"]):
        missing = sorted(RENDER_ATTRIBUTE_SET.difference(attributes))
        if missing:
            ok = fail(f"{label} primitive {index} is missing render attributes: {', '.join(missing)}") and ok
    return ok


def validate_grounded_origin(args, stats, label):
    if not stats["dimensions"]:
        return fail(f"{label} requires POSITION min/max bounds for grounded-origin check")
    ok = True
    min_y = float(stats["bounds_min"][1])
    max_y = float(stats["bounds_max"][1])
    if min_y < -args.origin_ground_tolerance or min_y > args.origin_ground_tolerance:
        ok = fail(f"{label} origin/contact plane should be at Y=0; bounds min.y is {min_y:.4f}") and ok
    if max_y <= min_y:
        ok = fail(f"{label} bounds should extend above the grounded origin") and ok
    x_size = max(float(stats["dimensions"][0]), 0.000001)
    z_size = max(float(stats["dimensions"][2]), 0.000001)
    center_x = (float(stats["bounds_min"][0]) + float(stats["bounds_max"][0])) * 0.5
    center_z = (float(stats["bounds_min"][2]) + float(stats["bounds_max"][2])) * 0.5
    allowed_x = max(args.origin_ground_tolerance, x_size * args.max_origin_offset_ratio)
    allowed_z = max(args.origin_ground_tolerance, z_size * args.max_origin_offset_ratio)
    if abs(center_x) > allowed_x:
        ok = fail(f"{label} footprint center.x {center_x:.4f} exceeds allowed grounded-origin offset {allowed_x:.4f}") and ok
    if abs(center_z) > allowed_z:
        ok = fail(f"{label} footprint center.z {center_z:.4f} exceeds allowed grounded-origin offset {allowed_z:.4f}") and ok
    return ok


def validate(args, stats, bin_chunk_count):
    ok = True
    print(f"file: {args.path}")
    print(f"nodes: {stats['node_count']}  meshes: {stats['mesh_count']}  primitives: {stats['primitive_count']}  bin_chunks: {bin_chunk_count}")
    print(f"triangles: {stats['triangle_count']}")
    if bin_chunk_count < 1:
        ok = fail("missing BIN chunk") and ok
    if stats["dimensions"]:
        dims = ", ".join(f"{value:.3f}" for value in stats["dimensions"])
        print(f"bounds dimensions ({stats['bounds_source']}): {dims} m")
    else:
        ok = fail("POSITION accessors do not expose min/max bounds") and ok

    if stats["triangle_count"] > args.max_triangles:
        ok = fail(f"triangle count {stats['triangle_count']} exceeds budget {args.max_triangles}") and ok

    if args.max_primitives is not None and stats["primitive_count"] > args.max_primitives:
        ok = fail(f"primitive count {stats['primitive_count']} exceeds budget {args.max_primitives}") and ok

    if args.max_dimension is not None and stats["dimensions"]:
        largest = max(stats["dimensions"])
        if largest > args.max_dimension:
            ok = fail(f"largest dimension {largest:.3f} m exceeds max {args.max_dimension:.3f} m") and ok

    if args.min_dimension is not None and stats["dimensions"]:
        largest = max(stats["dimensions"])
        if largest < args.min_dimension:
            ok = fail(f"largest dimension {largest:.3f} m is below min {args.min_dimension:.3f} m") and ok

    surface_tags = []
    for name in stats["names"]:
        match = SURFACE_PATTERN.search(name)
        if match is not None:
            surface_tags.append(match.group(1))
    if args.require_surface_tag and not surface_tags:
        ok = fail("no __surf_<surfaceid> tag found in node or mesh names") and ok
    if args.surface_id is not None and args.surface_id not in surface_tags:
        ok = fail(f"surface tag __surf_{args.surface_id} not found") and ok
    if surface_tags:
        print("surface tags: " + ", ".join(sorted(set(surface_tags))))

    wheel_names = [name for name in stats["names"] if WHEEL_PATTERN.search(name) is not None]
    if args.profile == "vehicle":
        if len(wheel_names) < 4:
            ok = fail(f"vehicle profile requires 4 wheel/tire nodes; found {len(wheel_names)}") and ok
        if args.max_dimension is None and stats["dimensions"] and max(stats["dimensions"]) > 1.0:
            ok = fail("vehicle profile expects RC-scale bounds; largest dimension exceeds 1.0 m") and ok
        ok = validate_vehicle(stats) and ok
    if wheel_names:
        print("wheel-like names: " + ", ".join(wheel_names))

    if args.profile == "heightmesh":
        ok = validate_heightmesh(args, stats) and ok

    if args.profile == "prop" or args.profile == "scatter":
        ok = validate_decoration_profile(args, stats, args.profile, surface_tags, wheel_names) and ok

    if args.require_render_attributes:
        ok = validate_render_attributes(stats, args.path.name) and ok

    if args.require_grounded_origin:
        ok = validate_grounded_origin(args, stats, args.path.name) and ok

    if ok:
        print("ok: GLB import contract checks passed")
    return ok


def main():
    parser = argparse.ArgumentParser(description="Validate Trailhead GLB import contracts.")
    parser.add_argument("path", type=Path)
    parser.add_argument("--profile", choices=["generic", "vehicle", "heightmesh", "prop", "scatter"], default="generic")
    parser.add_argument("--max-triangles", type=int, default=200000)
    parser.add_argument("--max-primitives", type=int)
    parser.add_argument("--max-dimension", type=float)
    parser.add_argument("--min-dimension", type=float)
    parser.add_argument("--expected-name")
    parser.add_argument("--require-surface-tag", action="store_true")
    parser.add_argument("--require-render-attributes", action="store_true")
    parser.add_argument("--require-grounded-origin", action="store_true")
    parser.add_argument("--origin-ground-tolerance", type=float, default=0.015)
    parser.add_argument("--max-origin-offset-ratio", type=float, default=0.4)
    parser.add_argument("--surface-id")
    parser.add_argument("--surface-id-map", type=Path)
    args = parser.parse_args()

    try:
        gltf, bin_chunk_count = read_glb(args.path)
    except Exception as exc:
        print(f"fail: {exc}")
        return 1
    stats = collect_stats(gltf)
    return 0 if validate(args, stats, bin_chunk_count) else 1


if __name__ == "__main__":
    sys.exit(main())
