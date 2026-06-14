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
BIN_CHUNK_TYPE = 0x004E4942
TRIANGLES = 4
TRIANGLE_STRIP = 5
TRIANGLE_FAN = 6
PRIMITIVE_MODES = {0, 1, 2, 3, 4, 5, 6}
COMPONENT_TYPE_INFO = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
ACCESSOR_COMPONENT_COUNTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT2": 4,
    "MAT3": 9,
    "MAT4": 16,
}
INDEX_COMPONENT_TYPES = {5121, 5123, 5125}
GEOMETRY_BLOCKING_EXTENSIONS = {
    "EXT_meshopt_compression",
    "KHR_draco_mesh_compression",
    "KHR_mesh_quantization",
}
FLOAT_TOLERANCE = 0.00001
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
VEHICLE_WHEEL_CHILD_NAME = "wheel_mesh"
VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE = 0.001
VEHICLE_WHEEL_PIVOT_TOLERANCE = 0.003
VEHICLE_WHEEL_MIN_DIAMETER = 0.035
VEHICLE_WHEEL_MAX_DIAMETER = 0.09
VEHICLE_WHEEL_MIN_WIDTH = 0.018
VEHICLE_WHEEL_MAX_WIDTH = 0.06
VEHICLE_WHEEL_ROUNDNESS_TOLERANCE = 0.2
VEHICLE_WHEEL_MAX_WIDTH_TO_DIAMETER_RATIO = 0.8
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


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def nonnegative_int(value):
    if is_int(value) and value >= 0:
        return value
    return None


def gltf_list(gltf, key):
    value = gltf.get(key, []) if isinstance(gltf, dict) else []
    return value if isinstance(value, list) else []


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
    bin_chunks = []
    chunk_index = 0
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("GLB chunk header is truncated")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_length % 4 != 0:
            raise ValueError("GLB chunk length is not 4-byte aligned")
        offset += 8
        if offset + chunk_length > len(data):
            raise ValueError("GLB chunk payload extends past declared file length")
        chunk_data = data[offset:offset + chunk_length]
        offset += chunk_length
        if chunk_type == JSON_CHUNK_TYPE:
            if chunk_index != 0:
                raise ValueError("GLB JSON chunk must be first")
            if json_chunk is not None:
                raise ValueError("GLB contains multiple JSON chunks")
            json_chunk = chunk_data
        elif chunk_type == BIN_CHUNK_TYPE:
            bin_chunks.append(chunk_data)
        chunk_index += 1
    if json_chunk is None:
        raise ValueError("missing JSON chunk")
    json_payload = json_chunk.rstrip(b" ")
    padding = json_chunk[len(json_payload):]
    if any(byte != 0x20 for byte in padding):
        raise ValueError("GLB JSON chunk padding must use spaces")
    return json.loads(json_payload.decode("utf-8")), bin_chunks


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
    accessors = gltf_list(gltf, "accessors")
    if accessor_index is None or accessor_index < 0 or accessor_index >= len(accessors):
        return 0
    accessor = accessors[accessor_index]
    if not isinstance(accessor, dict):
        return 0
    count = accessor.get("count", 0)
    return count if is_int(count) and count >= 0 else 0


def primitive_position_accessor(primitive):
    if not isinstance(primitive, dict):
        return None
    attributes = primitive.get("attributes", {})
    if not isinstance(attributes, dict):
        return None
    value = attributes.get("POSITION")
    if isinstance(value, int):
        return value
    return None


def primitive_triangle_count(gltf, primitive):
    if not isinstance(primitive, dict):
        return 0
    mode = primitive.get("mode", TRIANGLES)
    if not is_int(mode):
        mode = TRIANGLES
    index_accessor = primitive.get("indices")
    position_accessor = primitive_position_accessor(primitive)
    count = accessor_count(gltf, index_accessor if isinstance(index_accessor, int) else position_accessor)
    if mode == TRIANGLES:
        return count // 3
    if mode == TRIANGLE_STRIP or mode == TRIANGLE_FAN:
        return max(0, count - 2)
    return 0


def component_info(accessor):
    component_type = accessor.get("componentType") if isinstance(accessor, dict) else None
    accessor_type = accessor.get("type") if isinstance(accessor, dict) else None
    if component_type not in COMPONENT_TYPE_INFO or accessor_type not in ACCESSOR_COMPONENT_COUNTS:
        return None
    _format, component_size = COMPONENT_TYPE_INFO[component_type]
    component_count = ACCESSOR_COMPONENT_COUNTS[accessor_type]
    return component_type, accessor_type, component_size, component_count


def accessor_span(byte_offset, count, element_size, stride):
    if count <= 0:
        return byte_offset
    return byte_offset + (count - 1) * stride + element_size


def validate_count_for_mode(errors, label, mode, count):
    if mode == TRIANGLES and count % 3 != 0:
        errors.append(f"{label} TRIANGLES count {count} is not divisible by 3")
    if (mode == TRIANGLE_STRIP or mode == TRIANGLE_FAN) and count > 0 and count < 3:
        errors.append(f"{label} triangle strip/fan count {count} must be 0 or at least 3")


def validate_numeric_vector(errors, label, value, length):
    if not isinstance(value, list) or len(value) != length:
        errors.append(f"{label} must be a {length}-component array")
        return
    for component in value:
        if not isinstance(component, (int, float)) or isinstance(component, bool):
            errors.append(f"{label} contains a nonnumeric component")
            return
        if not math.isfinite(float(component)):
            errors.append(f"{label} contains a non-finite component")
            return


def validate_accessor_bounds_metadata(errors, label, accessor, component_count):
    for key in ("min", "max"):
        if key not in accessor:
            continue
        value = accessor.get(key)
        if not isinstance(value, list) or len(value) != component_count:
            errors.append(f"{label}.{key} must have {component_count} components")
            continue
        for component in value:
            if not isinstance(component, (int, float)) or isinstance(component, bool):
                errors.append(f"{label}.{key} contains a nonnumeric component")
                break
            if not math.isfinite(float(component)):
                errors.append(f"{label}.{key} contains a non-finite component")
                break


def validate_attribute_shape(errors, label, attribute_name, accessor_info):
    if accessor_info is None:
        return
    accessor_type = accessor_info["type"]
    component_type = accessor_info["component_type"]
    normalized = accessor_info["normalized"]
    if attribute_name == "POSITION":
        if accessor_type != "VEC3" or component_type != 5126:
            errors.append(f"{label} POSITION must be FLOAT VEC3")
    elif attribute_name == "NORMAL":
        if accessor_type != "VEC3" or component_type != 5126:
            errors.append(f"{label} NORMAL must be FLOAT VEC3")
    elif attribute_name == "TANGENT":
        if accessor_type != "VEC4" or component_type != 5126:
            errors.append(f"{label} TANGENT must be FLOAT VEC4")
    elif attribute_name.startswith("TEXCOORD_"):
        if accessor_type != "VEC2":
            errors.append(f"{label} {attribute_name} must be VEC2")
        if component_type not in (5121, 5123, 5126):
            errors.append(f"{label} {attribute_name} uses unsupported component type {component_type}")
        if component_type in (5121, 5123) and not normalized:
            errors.append(f"{label} {attribute_name} integer data must be normalized")
    elif attribute_name.startswith("COLOR_"):
        if accessor_type not in ("VEC3", "VEC4"):
            errors.append(f"{label} {attribute_name} must be VEC3 or VEC4")
    elif attribute_name.startswith("JOINTS_") or attribute_name.startswith("WEIGHTS_"):
        if accessor_type != "VEC4":
            errors.append(f"{label} {attribute_name} must be VEC4")


def read_accessor_scalars(bin_chunks, buffer_view_infos, accessor_infos, accessor_index):
    if accessor_index < 0 or accessor_index >= len(accessor_infos):
        return []
    accessor_info = accessor_infos[accessor_index]
    if accessor_info is None or accessor_info["type"] != "SCALAR":
        return []
    view_index = accessor_info["buffer_view"]
    if view_index is None or view_index < 0 or view_index >= len(buffer_view_infos):
        return []
    view_info = buffer_view_infos[view_index]
    if view_info is None or view_info["buffer"] != 0 or not bin_chunks:
        return []
    component_format = COMPONENT_TYPE_INFO[accessor_info["component_type"]][0]
    fmt = "<" + component_format
    start = view_info["byte_offset"] + accessor_info["byte_offset"]
    stride = accessor_info["stride"]
    values = []
    for index in range(accessor_info["count"]):
        offset = start + index * stride
        values.append(struct.unpack_from(fmt, bin_chunks[0], offset)[0])
    return values


def read_accessor_vectors(bin_chunks, buffer_view_infos, accessor_infos, accessor_index):
    if accessor_index < 0 or accessor_index >= len(accessor_infos):
        return []
    accessor_info = accessor_infos[accessor_index]
    if accessor_info is None:
        return []
    view_index = accessor_info["buffer_view"]
    if view_index is None or view_index < 0 or view_index >= len(buffer_view_infos):
        return []
    view_info = buffer_view_infos[view_index]
    if view_info is None or view_info["buffer"] != 0 or not bin_chunks:
        return []
    component_format = COMPONENT_TYPE_INFO[accessor_info["component_type"]][0]
    fmt = "<" + component_format
    start = view_info["byte_offset"] + accessor_info["byte_offset"]
    stride = accessor_info["stride"]
    vectors = []
    for row in range(accessor_info["count"]):
        row_offset = start + row * stride
        vector = []
        for component in range(accessor_info["component_count"]):
            component_offset = row_offset + component * accessor_info["component_size"]
            vector.append(struct.unpack_from(fmt, bin_chunks[0], component_offset)[0])
        vectors.append(vector)
    return vectors


def decoded_bounds_for_accessor(errors, label, bin_chunks, buffer_view_infos, accessor_infos, accessor_index):
    try:
        vectors = read_accessor_vectors(bin_chunks, buffer_view_infos, accessor_infos, accessor_index)
    except Exception as exc:
        errors.append(f"{label} could not be decoded: {exc}")
        return None
    if not vectors:
        return None
    bounds_min = [float("inf"), float("inf"), float("inf")]
    bounds_max = [float("-inf"), float("-inf"), float("-inf")]
    for vector in vectors:
        for axis in range(3):
            value = float(vector[axis])
            if not math.isfinite(value):
                errors.append(f"{label} contains non-finite POSITION data")
                return None
            bounds_min[axis] = min(bounds_min[axis], value)
            bounds_max[axis] = max(bounds_max[axis], value)
    return bounds_min, bounds_max


def validate_declared_bounds_match_decoded(errors, label, accessor, decoded_bounds):
    decoded_min, decoded_max = decoded_bounds
    for key, decoded in (("min", decoded_min), ("max", decoded_max)):
        declared = accessor.get(key)
        if not isinstance(declared, list) or len(declared) < 3:
            errors.append(f"{label}.{key} is required for POSITION accessors")
            continue
        for axis in range(3):
            if abs(float(declared[axis]) - decoded[axis]) > FLOAT_TOLERANCE:
                errors.append(f"{label}.{key} does not match decoded POSITION data")
                break


def texture_index_from_material_property(material, key):
    value = material.get(key)
    if isinstance(value, dict):
        index = value.get("index")
        if is_int(index):
            return index
    return None


def extension_names(value):
    if isinstance(value, list):
        return [str(name) for name in value]
    return []


def object_extensions(value):
    if isinstance(value, dict):
        extensions = value.get("extensions", {})
        if isinstance(extensions, dict):
            return set(str(name) for name in extensions.keys())
    return set()


def collect_reachable_nodes(nodes, roots):
    reachable = set()

    def visit(node_index):
        if node_index in reachable or node_index < 0 or node_index >= len(nodes):
            return
        reachable.add(node_index)
        node = nodes[node_index]
        if not isinstance(node, dict):
            return
        children = node.get("children", [])
        if isinstance(children, list):
            for child_index in children:
                if is_int(child_index):
                    visit(child_index)

    for root in roots:
        visit(root)
    return reachable


def validate_node_graph(errors, gltf, nodes, meshes, scenes):
    child_parent_counts = [0 for _node in nodes]
    child_map = [[] for _node in nodes]
    for index, node in enumerate(nodes):
        if not isinstance(node, dict):
            continue
        children = node.get("children", [])
        if not isinstance(children, list):
            continue
        for child_index in children:
            if is_int(child_index) and 0 <= child_index < len(nodes):
                child_parent_counts[child_index] += 1
                child_map[index].append(child_index)
    for index, parent_count in enumerate(child_parent_counts):
        if parent_count > 1:
            errors.append(f"nodes[{index}] has multiple parents")

    states = [0 for _node in nodes]

    def visit(node_index, stack):
        state = states[node_index]
        if state == 1:
            cycle = " -> ".join(f"nodes[{index}]" for index in stack + [node_index])
            errors.append(f"node hierarchy contains a cycle: {cycle}")
            return
        if state == 2:
            return
        states[node_index] = 1
        for child_index in child_map[node_index]:
            visit(child_index, stack + [node_index])
        states[node_index] = 2

    for index in range(len(nodes)):
        if states[index] == 0:
            visit(index, [])

    roots = scene_root_indices(gltf, nodes)
    reachable_nodes = collect_reachable_nodes(nodes, roots)
    reachable_meshes = set()
    for node_index in reachable_nodes:
        node = nodes[node_index]
        if isinstance(node, dict):
            mesh_index = node.get("mesh")
            if is_int(mesh_index) and 0 <= mesh_index < len(meshes):
                reachable_meshes.add(mesh_index)
    if meshes and not reachable_meshes:
        errors.append("default scene must reach at least one mesh")
    for mesh_index in range(len(meshes)):
        if mesh_index not in reachable_meshes:
            errors.append(f"meshes[{mesh_index}] is not reachable from the default scene")
    return reachable_nodes, reachable_meshes


def validate_glb_integrity(gltf, bin_chunks):
    errors = []
    decoded_position_bounds = {}
    if not isinstance(gltf, dict):
        errors.append("GLB JSON root must be an object")
        for error in errors:
            fail(error)
        return False, {}

    asset = gltf.get("asset")
    if not isinstance(asset, dict) or str(asset.get("version")) != "2.0":
        errors.append("glTF asset.version must be 2.0")

    for extension in extension_names(gltf.get("extensionsRequired")):
        errors.append(f"required glTF extension is unsupported by the Trailhead checker: {extension}")
    for extension in extension_names(gltf.get("extensionsUsed")):
        if extension in GEOMETRY_BLOCKING_EXTENSIONS:
            errors.append(f"geometry extension is unsupported by the Trailhead checker: {extension}")

    buffers = gltf_list(gltf, "buffers")
    buffer_views = gltf_list(gltf, "bufferViews")
    accessors = gltf_list(gltf, "accessors")
    meshes = gltf_list(gltf, "meshes")
    materials = gltf_list(gltf, "materials")
    nodes = gltf_list(gltf, "nodes")
    scenes = gltf_list(gltf, "scenes")
    images = gltf_list(gltf, "images")
    textures = gltf_list(gltf, "textures")
    samplers = gltf_list(gltf, "samplers")
    cameras = gltf_list(gltf, "cameras")
    skins = gltf_list(gltf, "skins")

    for key in ("buffers", "bufferViews", "accessors", "meshes", "materials", "nodes", "scenes", "images", "textures", "samplers", "cameras", "skins"):
        if key in gltf and not isinstance(gltf.get(key), list):
            errors.append(f"glTF {key} must be an array")

    validate_node_graph(errors, gltf, nodes, meshes, scenes)

    if len(bin_chunks) != 1:
        errors.append(f"GLB must contain exactly one BIN chunk; found {len(bin_chunks)}")
    if len(buffers) != 1:
        errors.append(f"GLB JSON must declare exactly one buffer; found {len(buffers)}")

    buffer_infos = []
    for index, buffer in enumerate(buffers):
        label = f"buffers[{index}]"
        if not isinstance(buffer, dict):
            errors.append(f"{label} must be an object")
            buffer_infos.append(None)
            continue
        byte_length = nonnegative_int(buffer.get("byteLength"))
        if byte_length is None:
            errors.append(f"{label}.byteLength must be a nonnegative integer")
        if buffer.get("uri") is not None:
            errors.append(f"{label}.uri is not allowed; Trailhead GLBs must be self-contained")
        if index == 0 and byte_length is not None and bin_chunks:
            if byte_length > len(bin_chunks[0]):
                errors.append(f"{label}.byteLength {byte_length} exceeds BIN chunk length {len(bin_chunks[0])}")
            if len(bin_chunks[0]) - byte_length > 3:
                errors.append(f"{label}.byteLength leaves more than 3 bytes of BIN padding")
        buffer_infos.append({"byte_length": byte_length})

    buffer_view_infos = []
    for index, view in enumerate(buffer_views):
        label = f"bufferViews[{index}]"
        if not isinstance(view, dict):
            errors.append(f"{label} must be an object")
            buffer_view_infos.append(None)
            continue
        buffer_index = view.get("buffer")
        byte_offset = nonnegative_int(view.get("byteOffset", 0))
        byte_length = nonnegative_int(view.get("byteLength"))
        if not is_int(buffer_index) or buffer_index < 0 or buffer_index >= len(buffers):
            errors.append(f"{label}.buffer references invalid buffer {buffer_index}")
        if byte_offset is None:
            errors.append(f"{label}.byteOffset must be a nonnegative integer")
        if byte_length is None:
            errors.append(f"{label}.byteLength must be a nonnegative integer")
        stride = view.get("byteStride")
        if stride is not None:
            if not is_int(stride) or stride < 4 or stride > 252 or stride % 4 != 0:
                errors.append(f"{label}.byteStride must be a multiple of 4 in the 4..252 range")
        target = view.get("target")
        if target is not None and target not in (34962, 34963):
            errors.append(f"{label}.target has unsupported value {target}")
        for extension in object_extensions(view).intersection(GEOMETRY_BLOCKING_EXTENSIONS):
            errors.append(f"{label} uses unsupported geometry extension {extension}")
        if (
            is_int(buffer_index)
            and 0 <= buffer_index < len(buffer_infos)
            and buffer_infos[buffer_index] is not None
            and byte_offset is not None
            and byte_length is not None
            and buffer_infos[buffer_index]["byte_length"] is not None
            and byte_offset + byte_length > buffer_infos[buffer_index]["byte_length"]
        ):
            errors.append(f"{label} byte range exceeds buffers[{buffer_index}].byteLength")
        buffer_view_infos.append({
            "buffer": buffer_index if is_int(buffer_index) else None,
            "byte_offset": byte_offset if byte_offset is not None else 0,
            "byte_length": byte_length if byte_length is not None else 0,
            "byte_stride": stride if is_int(stride) else None,
            "target": target,
        })

    accessor_infos = []
    for index, accessor in enumerate(accessors):
        label = f"accessors[{index}]"
        if not isinstance(accessor, dict):
            errors.append(f"{label} must be an object")
            accessor_infos.append(None)
            continue
        if "sparse" in accessor:
            errors.append(f"{label}.sparse is unsupported by the Trailhead GLB contract")
        for extension in object_extensions(accessor).intersection(GEOMETRY_BLOCKING_EXTENSIONS):
            errors.append(f"{label} uses unsupported geometry extension {extension}")
        view_index = accessor.get("bufferView")
        byte_offset = nonnegative_int(accessor.get("byteOffset", 0))
        count = nonnegative_int(accessor.get("count"))
        info = component_info(accessor)
        if view_index is None:
            errors.append(f"{label}.bufferView is required")
        elif not is_int(view_index) or view_index < 0 or view_index >= len(buffer_views):
            errors.append(f"{label}.bufferView references invalid bufferView {view_index}")
        if byte_offset is None:
            errors.append(f"{label}.byteOffset must be a nonnegative integer")
        if count is None:
            errors.append(f"{label}.count must be a nonnegative integer")
        if info is None:
            errors.append(f"{label} has unsupported componentType/type")
            accessor_infos.append(None)
            continue
        component_type, accessor_type, component_size, component_count = info
        element_size = component_size * component_count
        validate_accessor_bounds_metadata(errors, label, accessor, component_count)
        normalized = accessor.get("normalized", False)
        if not isinstance(normalized, bool):
            errors.append(f"{label}.normalized must be a boolean when present")
            normalized = False
        accessor_info = {
            "buffer_view": view_index if is_int(view_index) else None,
            "byte_offset": byte_offset if byte_offset is not None else 0,
            "count": count if count is not None else 0,
            "component_type": component_type,
            "type": accessor_type,
            "component_size": component_size,
            "component_count": component_count,
            "element_size": element_size,
            "normalized": normalized,
            "stride": element_size,
        }
        if is_int(view_index) and 0 <= view_index < len(buffer_view_infos) and buffer_view_infos[view_index] is not None:
            view_info = buffer_view_infos[view_index]
            stride = view_info["byte_stride"] if view_info["byte_stride"] is not None else element_size
            accessor_info["stride"] = stride
            if stride < element_size:
                errors.append(f"{label} element size {element_size} exceeds bufferView stride {stride}")
            if byte_offset is not None and byte_offset % component_size != 0:
                errors.append(f"{label}.byteOffset is not aligned to component size {component_size}")
            absolute_offset = view_info["byte_offset"] + (byte_offset if byte_offset is not None else 0)
            if absolute_offset % component_size != 0:
                errors.append(f"{label} absolute byte offset is not aligned to component size {component_size}")
            required_span = accessor_span(
                byte_offset if byte_offset is not None else 0,
                count if count is not None else 0,
                element_size,
                stride,
            )
            if required_span > view_info["byte_length"]:
                errors.append(f"{label} byte range exceeds bufferViews[{view_index}].byteLength")
        accessor_infos.append(accessor_info)

    for index, image in enumerate(images):
        label = f"images[{index}]"
        if not isinstance(image, dict):
            errors.append(f"{label} must be an object")
            continue
        view_index = image.get("bufferView")
        uri = image.get("uri")
        if uri is not None:
            errors.append(f"{label}.uri is not allowed; embed image data in the GLB BIN chunk")
        if view_index is not None and (not is_int(view_index) or view_index < 0 or view_index >= len(buffer_views)):
            errors.append(f"{label}.bufferView references invalid bufferView {view_index}")

    for index, texture in enumerate(textures):
        label = f"textures[{index}]"
        if not isinstance(texture, dict):
            errors.append(f"{label} must be an object")
            continue
        source = texture.get("source")
        sampler = texture.get("sampler")
        if source is not None and (not is_int(source) or source < 0 or source >= len(images)):
            errors.append(f"{label}.source references invalid image {source}")
        if sampler is not None and (not is_int(sampler) or sampler < 0 or sampler >= len(samplers)):
            errors.append(f"{label}.sampler references invalid sampler {sampler}")

    for index, material in enumerate(materials):
        label = f"materials[{index}]"
        if not isinstance(material, dict):
            errors.append(f"{label} must be an object")
            continue
        pbr = material.get("pbrMetallicRoughness", {})
        if isinstance(pbr, dict):
            for key in ("baseColorTexture", "metallicRoughnessTexture"):
                texture_index = texture_index_from_material_property(pbr, key)
                if texture_index is not None and (texture_index < 0 or texture_index >= len(textures)):
                    errors.append(f"{label}.pbrMetallicRoughness.{key}.index references invalid texture {texture_index}")
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            texture_index = texture_index_from_material_property(material, key)
            if texture_index is not None and (texture_index < 0 or texture_index >= len(textures)):
                errors.append(f"{label}.{key}.index references invalid texture {texture_index}")

    for mesh_index, mesh in enumerate(meshes):
        mesh_label = f"meshes[{mesh_index}]"
        if not isinstance(mesh, dict):
            errors.append(f"{mesh_label} must be an object")
            continue
        primitives = mesh.get("primitives")
        if not isinstance(primitives, list) or not primitives:
            errors.append(f"{mesh_label}.primitives must be a nonempty array")
            continue
        for primitive_index, primitive in enumerate(primitives):
            label = f"{mesh_label}.primitives[{primitive_index}]"
            if not isinstance(primitive, dict):
                errors.append(f"{label} must be an object")
                continue
            for extension in object_extensions(primitive).intersection(GEOMETRY_BLOCKING_EXTENSIONS):
                errors.append(f"{label} uses unsupported geometry extension {extension}")
            mode = primitive.get("mode", TRIANGLES)
            if not is_int(mode) or mode not in PRIMITIVE_MODES:
                errors.append(f"{label}.mode has unsupported value {mode}")
                mode = TRIANGLES
            material_index = primitive.get("material")
            if material_index is not None and (not is_int(material_index) or material_index < 0 or material_index >= len(materials)):
                errors.append(f"{label}.material references invalid material {material_index}")
            attributes = primitive.get("attributes")
            if not isinstance(attributes, dict) or not attributes:
                errors.append(f"{label}.attributes must be a nonempty object")
                continue
            position_index = attributes.get("POSITION")
            position_count = None
            if not is_int(position_index) or position_index < 0 or position_index >= len(accessor_infos) or accessor_infos[position_index] is None:
                errors.append(f"{label}.attributes.POSITION references invalid accessor {position_index}")
            else:
                position_count = accessor_infos[position_index]["count"]
                position_info = accessor_infos[position_index]
                if position_info["type"] == "VEC3" and position_info["component_type"] == 5126:
                    if position_index not in decoded_position_bounds:
                        bounds_pair = decoded_bounds_for_accessor(
                            errors,
                            f"accessors[{position_index}]",
                            bin_chunks,
                            buffer_view_infos,
                            accessor_infos,
                            position_index,
                        )
                        if bounds_pair is not None:
                            decoded_position_bounds[position_index] = bounds_pair
                            validate_declared_bounds_match_decoded(
                                errors,
                                f"accessors[{position_index}]",
                                accessors[position_index],
                                bounds_pair,
                            )
            for attribute_name, accessor_index in attributes.items():
                if not isinstance(attribute_name, str):
                    errors.append(f"{label}.attributes contains a non-string semantic")
                    continue
                if not is_int(accessor_index) or accessor_index < 0 or accessor_index >= len(accessor_infos) or accessor_infos[accessor_index] is None:
                    errors.append(f"{label}.attributes.{attribute_name} references invalid accessor {accessor_index}")
                    continue
                accessor_info = accessor_infos[accessor_index]
                validate_attribute_shape(errors, label, attribute_name, accessor_info)
                if position_count is not None and accessor_info["count"] != position_count:
                    errors.append(f"{label}.attributes.{attribute_name} count {accessor_info['count']} does not match POSITION count {position_count}")
                view_index = accessor_info["buffer_view"]
                if view_index is not None and 0 <= view_index < len(buffer_view_infos) and buffer_view_infos[view_index] is not None:
                    target = buffer_view_infos[view_index]["target"]
                    if target is not None and target != 34962:
                        errors.append(f"{label}.attributes.{attribute_name} bufferView target should be ARRAY_BUFFER")
            indices_index = primitive.get("indices")
            draw_count = position_count if position_count is not None else 0
            if indices_index is not None:
                if not is_int(indices_index) or indices_index < 0 or indices_index >= len(accessor_infos) or accessor_infos[indices_index] is None:
                    errors.append(f"{label}.indices references invalid accessor {indices_index}")
                else:
                    index_info = accessor_infos[indices_index]
                    draw_count = index_info["count"]
                    if index_info["type"] != "SCALAR":
                        errors.append(f"{label}.indices accessor must be SCALAR")
                    if index_info["component_type"] not in INDEX_COMPONENT_TYPES:
                        errors.append(f"{label}.indices accessor must use an unsigned integer component type")
                    view_index = index_info["buffer_view"]
                    if view_index is not None and 0 <= view_index < len(buffer_view_infos) and buffer_view_infos[view_index] is not None:
                        target = buffer_view_infos[view_index]["target"]
                        if target is not None and target != 34963:
                            errors.append(f"{label}.indices bufferView target should be ELEMENT_ARRAY_BUFFER")
                    if position_count is not None and index_info["type"] == "SCALAR" and index_info["component_type"] in INDEX_COMPONENT_TYPES:
                        try:
                            indices = read_accessor_scalars(bin_chunks, buffer_view_infos, accessor_infos, indices_index)
                            if indices:
                                max_index = max(indices)
                                if max_index >= position_count:
                                    errors.append(f"{label}.indices contains index {max_index} but POSITION count is {position_count}")
                        except Exception as exc:
                            errors.append(f"{label}.indices could not be decoded: {exc}")
            validate_count_for_mode(errors, label, mode, draw_count)

    for index, scene in enumerate(scenes):
        label = f"scenes[{index}]"
        if not isinstance(scene, dict):
            errors.append(f"{label} must be an object")
            continue
        scene_nodes = scene.get("nodes", [])
        if not isinstance(scene_nodes, list):
            errors.append(f"{label}.nodes must be an array")
            continue
        for node_index in scene_nodes:
            if not is_int(node_index) or node_index < 0 or node_index >= len(nodes):
                errors.append(f"{label}.nodes references invalid node {node_index}")

    scene_index = gltf.get("scene")
    if scene_index is not None and (not is_int(scene_index) or scene_index < 0 or scene_index >= len(scenes)):
        errors.append(f"scene references invalid scene {scene_index}")

    for index, node in enumerate(nodes):
        label = f"nodes[{index}]"
        if not isinstance(node, dict):
            errors.append(f"{label} must be an object")
            continue
        mesh_index = node.get("mesh")
        if mesh_index is not None and (not is_int(mesh_index) or mesh_index < 0 or mesh_index >= len(meshes)):
            errors.append(f"{label}.mesh references invalid mesh {mesh_index}")
        camera_index = node.get("camera")
        if camera_index is not None and (not is_int(camera_index) or camera_index < 0 or camera_index >= len(cameras)):
            errors.append(f"{label}.camera references invalid camera {camera_index}")
        skin_index = node.get("skin")
        if skin_index is not None and (not is_int(skin_index) or skin_index < 0 or skin_index >= len(skins)):
            errors.append(f"{label}.skin references invalid skin {skin_index}")
        children = node.get("children", [])
        if not isinstance(children, list):
            errors.append(f"{label}.children must be an array")
        else:
            for child_index in children:
                if not is_int(child_index) or child_index < 0 or child_index >= len(nodes):
                    errors.append(f"{label}.children references invalid node {child_index}")
                elif child_index == index:
                    errors.append(f"{label}.children must not reference itself")
        if "matrix" in node:
            validate_numeric_vector(errors, f"{label}.matrix", node.get("matrix"), 16)
            for key in ("translation", "rotation", "scale"):
                if key in node:
                    errors.append(f"{label} must not mix matrix with {key}")
        else:
            if "translation" in node:
                validate_numeric_vector(errors, f"{label}.translation", node.get("translation"), 3)
            if "rotation" in node:
                validate_numeric_vector(errors, f"{label}.rotation", node.get("rotation"), 4)
            if "scale" in node:
                validate_numeric_vector(errors, f"{label}.scale", node.get("scale"), 3)

    ok = True
    for error in errors:
        ok = fail(error) and ok
    return ok, decoded_position_bounds


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


def node_rotation(node):
    if node_matrix_values(node) is not None:
        return [0.0, 0.0, 0.0, 1.0]
    return vector_from_property(node.get("rotation"), 4, [0.0, 0.0, 0.0, 1.0])


def node_scale(node):
    if node_matrix_values(node) is not None:
        return [1.0, 1.0, 1.0]
    return vector_from_property(node.get("scale"), 3, [1.0, 1.0, 1.0])


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


def accessor_bounds_for_primitive(gltf, primitive, decoded_position_bounds):
    accessors = gltf_list(gltf, "accessors")
    position_accessor = primitive_position_accessor(primitive)
    if position_accessor is None or position_accessor < 0 or position_accessor >= len(accessors):
        return None
    if position_accessor in decoded_position_bounds:
        return decoded_position_bounds[position_accessor]
    accessor = accessors[position_accessor]
    if not isinstance(accessor, dict):
        return None
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
    scenes = gltf_list(gltf, "scenes")
    scene_index = gltf.get("scene") if isinstance(gltf, dict) else None
    if is_int(scene_index) and 0 <= scene_index < len(scenes):
        scene = scenes[scene_index]
        roots = scene.get("nodes", []) if isinstance(scene, dict) else []
        if isinstance(roots, list):
            return [index for index in roots if is_int(index) and 0 <= index < len(nodes)]
    child_indices = set()
    for node in nodes:
        if not isinstance(node, dict):
            continue
        children = node.get("children", [])
        if isinstance(children, list):
            child_indices.update(index for index in children if is_int(index) and 0 <= index < len(nodes))
    return [index for index in range(len(nodes)) if index not in child_indices]


def collect_stats(gltf, decoded_position_bounds=None):
    if decoded_position_bounds is None:
        decoded_position_bounds = {}
    meshes = gltf_list(gltf, "meshes")
    nodes = gltf_list(gltf, "nodes")
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
        primitives = mesh.get("primitives", []) if isinstance(mesh, dict) else []
        if not isinstance(primitives, list):
            primitives = []
        for primitive in primitives:
            primitive_count += 1
            attributes = primitive.get("attributes", {}) if isinstance(primitive, dict) else {}
            if isinstance(attributes, dict):
                primitive_attributes.append(sorted(attributes.keys()))
            else:
                primitive_attributes.append([])
            triangle_count += primitive_triangle_count(gltf, primitive)
            bounds_pair = accessor_bounds_for_primitive(gltf, primitive, decoded_position_bounds)
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
        if not isinstance(node, dict):
            return
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
        if not isinstance(node, dict):
            node = {}
        node_name = str(node.get("name", ""))
        children = node.get("children", [])
        mesh_index = node.get("mesh")
        node_summaries.append({
            "index": index,
            "name": node_name,
            "translation": node_translation(node),
            "rotation": node_rotation(node),
            "scale": node_scale(node),
            "has_matrix": node_matrix_values(node) is not None,
            "children": children if isinstance(children, list) else [],
            "mesh": mesh_index if isinstance(mesh_index, int) else None,
        })
        if "name" in node:
            names.append(node_name)
    for mesh in meshes:
        if isinstance(mesh, dict) and "name" in mesh:
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
        "mesh_bounds": mesh_bounds,
        "mesh_names": [str(mesh.get("name", "")) if isinstance(mesh, dict) else "" for mesh in meshes],
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
        if socket_node["mesh"] is not None:
            ok = fail(f"{socket_name} should be a pure socket node and must not own a mesh directly") and ok
        ok = validate_vehicle_socket_transform(socket_name, socket_node) and ok
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
            continue
        if len(mesh_children) != 1:
            ok = fail(f"{socket_name} should own exactly one direct mesh child; found {len(mesh_children)}") and ok
            continue
        ok = validate_vehicle_wheel_child(socket_name, mesh_children[0], stats) and ok
    return ok


def identity_quaternion(rotation):
    if len(rotation) < 4:
        return False
    positive_w = [0.0, 0.0, 0.0, 1.0]
    negative_w = [0.0, 0.0, 0.0, -1.0]
    return (
        all(abs(float(rotation[index]) - positive_w[index]) <= VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE for index in range(4))
        or all(abs(float(rotation[index]) - negative_w[index]) <= VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE for index in range(4))
    )


def validate_vehicle_socket_transform(socket_name, socket_node):
    ok = True
    if socket_node["has_matrix"]:
        ok = fail(f"{socket_name} should not use a matrix transform; use translation-only socket pivots") and ok
    if not identity_quaternion(socket_node["rotation"]):
        ok = fail(f"{socket_name} rotation should be identity; got {socket_node['rotation']}") and ok
    for value in socket_node["scale"]:
        if abs(float(value) - 1.0) > VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE:
            ok = fail(f"{socket_name} scale should be 1; got {socket_node['scale']}") and ok
            break
    return ok


def validate_vehicle_wheel_child(socket_name, wheel_node, stats):
    ok = True
    if wheel_node["name"] != VEHICLE_WHEEL_CHILD_NAME:
        ok = fail(f"{socket_name} direct mesh child should be named {VEHICLE_WHEEL_CHILD_NAME}; got {wheel_node['name']}") and ok
    if wheel_node["has_matrix"]:
        ok = fail(f"{socket_name}/{wheel_node['name']} should not use a matrix transform; bake transforms into mesh data") and ok
    for axis, value in enumerate(wheel_node["translation"]):
        if abs(float(value)) > VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE:
            ok = fail(f"{socket_name}/{wheel_node['name']} local translation should be zero; got {wheel_node['translation']}") and ok
            break
    if not identity_quaternion(wheel_node["rotation"]):
        ok = fail(f"{socket_name}/{wheel_node['name']} local rotation should be identity; got {wheel_node['rotation']}") and ok
    for value in wheel_node["scale"]:
        if abs(float(value) - 1.0) > VEHICLE_WHEEL_CHILD_TRANSFORM_TOLERANCE:
            ok = fail(f"{socket_name}/{wheel_node['name']} local scale should be 1; got {wheel_node['scale']}") and ok
            break

    mesh_index = wheel_node["mesh"]
    mesh_bounds = stats["mesh_bounds"][mesh_index] if mesh_index is not None and 0 <= mesh_index < len(stats["mesh_bounds"]) else None
    if mesh_bounds is None:
        ok = fail(f"{socket_name}/{wheel_node['name']} mesh must expose decoded POSITION bounds") and ok
        return ok
    bounds_min, bounds_max = mesh_bounds
    dimensions = [bounds_max[index] - bounds_min[index] for index in range(3)]
    center = [(bounds_min[index] + bounds_max[index]) * 0.5 for index in range(3)]
    for axis, value in enumerate(center):
        if abs(float(value)) > VEHICLE_WHEEL_PIVOT_TOLERANCE:
            ok = fail(f"{socket_name}/{wheel_node['name']} mesh pivot should be centered; local bounds center is {center}") and ok
            break
    for axis, axis_name in enumerate(("X", "Y", "Z")):
        if bounds_min[axis] >= 0.0 or bounds_max[axis] <= 0.0:
            ok = fail(f"{socket_name}/{wheel_node['name']} mesh bounds should straddle local {axis_name}=0 pivot; got min {bounds_min[axis]:.4f}, max {bounds_max[axis]:.4f}") and ok
    width = dimensions[1]
    diameter_x = dimensions[0]
    diameter_z = dimensions[2]
    if width < VEHICLE_WHEEL_MIN_WIDTH or width > VEHICLE_WHEEL_MAX_WIDTH:
        ok = fail(f"{socket_name}/{wheel_node['name']} wheel width {width:.3f} m is outside expected {VEHICLE_WHEEL_MIN_WIDTH:.3f}..{VEHICLE_WHEEL_MAX_WIDTH:.3f} m") and ok
    for axis_name, diameter in (("X", diameter_x), ("Z", diameter_z)):
        if diameter < VEHICLE_WHEEL_MIN_DIAMETER or diameter > VEHICLE_WHEEL_MAX_DIAMETER:
            ok = fail(f"{socket_name}/{wheel_node['name']} wheel {axis_name} diameter {diameter:.3f} m is outside expected {VEHICLE_WHEEL_MIN_DIAMETER:.3f}..{VEHICLE_WHEEL_MAX_DIAMETER:.3f} m") and ok
    larger_diameter = max(diameter_x, diameter_z)
    if larger_diameter > 0.0 and abs(diameter_x - diameter_z) / larger_diameter > VEHICLE_WHEEL_ROUNDNESS_TOLERANCE:
        ok = fail(f"{socket_name}/{wheel_node['name']} wheel X/Z diameters should be similar; got {diameter_x:.3f} m and {diameter_z:.3f} m") and ok
    smaller_diameter = min(diameter_x, diameter_z)
    if smaller_diameter > 0.0 and width / smaller_diameter >= VEHICLE_WHEEL_MAX_WIDTH_TO_DIAMETER_RATIO:
        ok = fail(f"{socket_name}/{wheel_node['name']} wheel width {width:.3f} m should be less than {VEHICLE_WHEEL_MAX_WIDTH_TO_DIAMETER_RATIO:.2f}x diameter {smaller_diameter:.3f} m") and ok
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


def validate(args, stats, bin_chunk_count, integrity_ok):
    ok = integrity_ok
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
        gltf, bin_chunks = read_glb(args.path)
    except Exception as exc:
        print(f"fail: {exc}")
        return 1
    integrity_ok, decoded_position_bounds = validate_glb_integrity(gltf, bin_chunks)
    stats = collect_stats(gltf, decoded_position_bounds)
    return 0 if validate(args, stats, len(bin_chunks), integrity_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
