import json
import math
import struct


def pad4(data, pad_byte=b" "):
    padding = (-len(data)) % 4
    if padding:
        data += pad_byte * padding
    return data


def pack_positions(vertices):
    return b"".join(struct.pack("<fff", vertex[0], vertex[1], vertex[2]) for vertex in vertices)


def pack_normals(normals):
    return b"".join(struct.pack("<fff", normal[0], normal[1], normal[2]) for normal in normals)


def pack_uvs(uvs):
    return b"".join(struct.pack("<ff", uv[0], uv[1]) for uv in uvs)


def pack_indices(indices):
    return b"".join(struct.pack("<H", index) for index in indices)


def append_aligned(buffer, chunk, alignment=4):
    padding = (-len(buffer)) % alignment
    if padding:
        buffer.extend(b"\0" * padding)
    offset = len(buffer)
    buffer.extend(chunk)
    return offset


def bounds(vertices):
    mins = [min(vertex[index] for vertex in vertices) for index in range(3)]
    maxs = [max(vertex[index] for vertex in vertices) for index in range(3)]
    return mins, maxs


def vector_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vector_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vector_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vector_cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def vector_normalized(value, fallback=(0.0, 1.0, 0.0)):
    length = math.sqrt(vector_dot(value, value))
    if length <= 0.000001:
        return fallback
    return (value[0] / length, value[1] / length, value[2] / length)


def mesh_center(vertices):
    count = float(len(vertices))
    return (
        sum(vertex[0] for vertex in vertices) / count,
        sum(vertex[1] for vertex in vertices) / count,
        sum(vertex[2] for vertex in vertices) / count,
    )


def compute_normals(vertices, indices):
    center = mesh_center(vertices)
    normal_sums = [(0.0, 0.0, 0.0) for _vertex in vertices]
    for index in range(0, len(indices), 3):
        if index + 2 >= len(indices):
            break
        ia, ib, ic = indices[index:index + 3]
        va = vertices[ia]
        vb = vertices[ib]
        vc = vertices[ic]
        normal = vector_cross(vector_sub(vb, va), vector_sub(vc, va))
        face_center = (
            (va[0] + vb[0] + vc[0]) / 3.0,
            (va[1] + vb[1] + vc[1]) / 3.0,
            (va[2] + vb[2] + vc[2]) / 3.0,
        )
        if vector_dot(normal, vector_sub(face_center, center)) < 0.0:
            normal = (-normal[0], -normal[1], -normal[2])
        for vertex_index in (ia, ib, ic):
            normal_sums[vertex_index] = vector_add(normal_sums[vertex_index], normal)
    return [vector_normalized(normal) for normal in normal_sums]


def compute_uvs(vertices):
    mins, maxs = bounds(vertices)
    extents = [maxs[index] - mins[index] for index in range(3)]
    axes = sorted(range(3), key=lambda index: extents[index], reverse=True)[:2]
    u_axis = axes[0]
    v_axis = axes[1]
    u_extent = max(extents[u_axis], 0.000001)
    v_extent = max(extents[v_axis], 0.000001)
    return [
        (
            (vertex[u_axis] - mins[u_axis]) / u_extent,
            (vertex[v_axis] - mins[v_axis]) / v_extent,
        )
        for vertex in vertices
    ]


def part(mesh, color, part_name):
    vertices, indices = mesh
    return vertices, indices, color, part_name


def write_glb_parts(path, asset_name, parts, generator, roughness_factor, surface_id="", double_sided=False):
    node_name = asset_name
    if surface_id:
        node_name = asset_name + "__surf_" + surface_id
    bin_data = bytearray()
    buffer_views = []
    accessors = []
    primitives = []
    materials = []
    for part_index, mesh_part in enumerate(parts):
        vertices, indices, color, part_name = mesh_part
        position_data = pack_positions(vertices)
        normal_data = pack_normals(compute_normals(vertices, indices))
        uv_data = pack_uvs(compute_uvs(vertices))
        index_data = pack_indices(indices)
        position_offset = append_aligned(bin_data, position_data)
        normal_offset = append_aligned(bin_data, normal_data)
        uv_offset = append_aligned(bin_data, uv_data)
        index_offset = append_aligned(bin_data, index_data, 2)
        mins, maxs = bounds(vertices)
        position_view = len(buffer_views)
        normal_view = position_view + 1
        uv_view = position_view + 2
        index_view = position_view + 3
        position_accessor = len(accessors)
        normal_accessor = position_accessor + 1
        uv_accessor = position_accessor + 2
        index_accessor = position_accessor + 3
        buffer_views.extend([
            {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
            {"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_data), "target": 34962},
            {"buffer": 0, "byteOffset": uv_offset, "byteLength": len(uv_data), "target": 34962},
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
                "bufferView": normal_view,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC3",
            },
            {
                "bufferView": uv_view,
                "byteOffset": 0,
                "componentType": 5126,
                "count": len(vertices),
                "type": "VEC2",
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
            "attributes": {
                "POSITION": position_accessor,
                "NORMAL": normal_accessor,
                "TEXCOORD_0": uv_accessor,
            },
            "indices": index_accessor,
            "mode": 4,
            "material": part_index,
        })
        material = {
            "name": part_name + "_mat",
            "pbrMetallicRoughness": {
                "baseColorFactor": color,
                "roughnessFactor": roughness_factor,
                "metallicFactor": 0.0,
            },
        }
        if double_sided:
            material["doubleSided"] = True
        materials.append(material)
    bin_chunk = pad4(bytes(bin_data), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": generator},
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


def write_glb(path, asset_name, mesh, color, generator, roughness_factor, surface_id=""):
    write_glb_parts(
        path,
        asset_name,
        [part(mesh, color, asset_name)],
        generator=generator,
        roughness_factor=roughness_factor,
        surface_id=surface_id,
    )
