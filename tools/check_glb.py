#!/usr/bin/env python3
import argparse
import json
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


def collect_stats(gltf):
    meshes = gltf.get("meshes", [])
    nodes = gltf.get("nodes", [])
    accessors = gltf.get("accessors", [])
    triangle_count = 0
    primitive_count = 0
    primitive_attributes = []
    bounds_min = [float("inf"), float("inf"), float("inf")]
    bounds_max = [float("-inf"), float("-inf"), float("-inf")]
    has_bounds = False

    for mesh in meshes:
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            attributes = primitive.get("attributes", {})
            if isinstance(attributes, dict):
                primitive_attributes.append(sorted(attributes.keys()))
            else:
                primitive_attributes.append([])
            triangle_count += primitive_triangle_count(gltf, primitive)
            position_accessor = primitive_position_accessor(primitive)
            if position_accessor is not None and 0 <= position_accessor < len(accessors):
                accessor = accessors[position_accessor]
                amin = accessor.get("min")
                amax = accessor.get("max")
                if isinstance(amin, list) and isinstance(amax, list) and len(amin) >= 3 and len(amax) >= 3:
                    has_bounds = True
                    for index in range(3):
                        bounds_min[index] = min(bounds_min[index], float(amin[index]))
                        bounds_max[index] = max(bounds_max[index], float(amax[index]))

    names = []
    node_summaries = []
    for node in nodes:
        if "name" in node:
            node_name = str(node["name"])
            names.append(node_name)
            translation = node.get("translation", [0.0, 0.0, 0.0])
            node_summaries.append({
                "name": node_name,
                "translation": translation if isinstance(translation, list) else [0.0, 0.0, 0.0],
            })
    for mesh in meshes:
        if "name" in mesh:
            names.append(str(mesh["name"]))

    if has_bounds:
        dimensions = [bounds_max[index] - bounds_min[index] for index in range(3)]
    else:
        dimensions = []
    return {
        "mesh_count": len(meshes),
        "node_count": len(nodes),
        "primitive_count": primitive_count,
        "triangle_count": triangle_count,
        "bounds_min": bounds_min if has_bounds else [],
        "bounds_max": bounds_max if has_bounds else [],
        "dimensions": dimensions,
        "names": names,
        "nodes": node_summaries,
        "primitive_attributes": primitive_attributes,
    }


def validate_vehicle(stats):
    ok = True
    node_names = [node["name"] for node in stats["nodes"]]
    if "rc_buggy" not in node_names:
        ok = fail("vehicle profile requires rc_buggy root node") and ok
    for socket_name, expected_position in VEHICLE_WHEEL_SOCKET_POSITIONS.items():
        matching_nodes = [node for node in stats["nodes"] if node["name"] == socket_name]
        if len(matching_nodes) != 1:
            ok = fail(f"vehicle profile requires exactly one {socket_name} node; found {len(matching_nodes)}") and ok
            continue
        translation = matching_nodes[0]["translation"]
        if len(translation) < 3:
            ok = fail(f"{socket_name} translation should have 3 components") and ok
            continue
        for axis in range(3):
            delta = abs(float(translation[axis]) - expected_position[axis])
            if delta > VEHICLE_SOCKET_TOLERANCE:
                ok = fail(f"{socket_name} translation expected {expected_position}, got {translation}") and ok
                break
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


def validate(args, stats, bin_chunk_count):
    ok = True
    print(f"file: {args.path}")
    print(f"nodes: {stats['node_count']}  meshes: {stats['mesh_count']}  primitives: {stats['primitive_count']}  bin_chunks: {bin_chunk_count}")
    print(f"triangles: {stats['triangle_count']}")
    if bin_chunk_count < 1:
        ok = fail("missing BIN chunk") and ok
    if stats["dimensions"]:
        dims = ", ".join(f"{value:.3f}" for value in stats["dimensions"])
        print(f"bounds dimensions: {dims} m")
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
