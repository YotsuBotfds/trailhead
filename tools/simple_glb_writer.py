import json
import struct


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


def part(mesh, color, part_name):
    vertices, indices = mesh
    return vertices, indices, color, part_name


def write_glb_parts(path, asset_name, parts, generator, roughness_factor, surface_id=""):
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
                "roughnessFactor": roughness_factor,
                "metallicFactor": 0.0,
            },
        })
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
