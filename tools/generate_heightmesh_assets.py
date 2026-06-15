#!/usr/bin/env python3
import argparse
import inspect
import importlib.util
import json
import math
import struct
import sys
import zlib
from pathlib import Path

from terrain_def_parser import load_terrain_def

OUT_DIR = Path("assets/models/terrain")
COLLISION_OUT_DIR = Path("data/collision")
GLB_FILENAME = "cedar_hollow_heightmesh.glb"
SURFACE_ID_FILENAME = "cedar_hollow_surface_id.png"
DEFAULT_TERRAIN_SEED = 20260615
DEFAULT_TERRAIN_VERSION = "cedar_hollow_t2_height_authority_v1"
DEFAULT_HEIGHT_AUTHORITY = "eroded"
HEIGHT_AUTHORITY_CHOICES = ("legacy", "eroded", "auto")
EROSION_WORK_GRID_MIN = 512
EROSION_WORK_GRID_MAX = 1024
TERRAIN_BASE_ELEVATION = -0.035
EXTENDED_TRAIL_START_Z = -10.6
EXTENDED_TRAIL_END_Z = -68.0
EXTENDED_TRAIL_HALF_WIDTH = 0.72
EXTENDED_TRAIL_EDGE_BLEND = 0.42
EROSION_MODULE_PATH = Path(__file__).with_name("erosion.py")
TERRAIN_DEF = load_terrain_def()
X_MIN, Z_MIN = TERRAIN_DEF.bounds_min_xz
X_MAX, Z_MAX = TERRAIN_DEF.bounds_max_xz
GRID_X, GRID_Z = TERRAIN_DEF.visual_grid
COLLISION_GRID_X, COLLISION_GRID_Z = TERRAIN_DEF.collision_grid
SURFACE_MAP_WIDTH, SURFACE_MAP_HEIGHT = TERRAIN_DEF.surface_map_size
_HEIGHT_AUTHORITY = None
_erosion_module = None

if EROSION_MODULE_PATH.exists():
    _erosion_spec = importlib.util.spec_from_file_location("trailhead_erosion", EROSION_MODULE_PATH)
    if _erosion_spec is None or _erosion_spec.loader is None:
        raise RuntimeError(f"could not load erosion module: {EROSION_MODULE_PATH}")
    _erosion_module = importlib.util.module_from_spec(_erosion_spec)
    sys.modules[_erosion_spec.name] = _erosion_module
    _erosion_spec.loader.exec_module(_erosion_module)

if _erosion_module is None:
    _build_eroded_heightfield = None
    _sample_heightfield = None
else:
    try:
        _build_eroded_heightfield = _erosion_module.build_eroded_heightfield
        _sample_heightfield = _erosion_module.sample_heightfield
    except AttributeError as exc:
        raise RuntimeError(
            "tools/erosion.py must expose build_eroded_heightfield(...) and sample_heightfield(...)."
        ) from exc


def parse_args():
    parser = argparse.ArgumentParser(description="Generate Trailhead Cedar Hollow terrain assets.")
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR, help="Directory to write generated terrain assets.")
    parser.add_argument(
        "--collision-out-dir",
        type=Path,
        default=None,
        help="Directory to write generated HeightMapShape3D collision tiles.",
    )
    parser.add_argument(
        "--terrain-seed",
        type=int,
        default=DEFAULT_TERRAIN_SEED,
        help="Deterministic seed passed to the erosion height authority.",
    )
    parser.add_argument(
        "--terrain-version",
        default=DEFAULT_TERRAIN_VERSION,
        help="Version string passed to the erosion height authority for byte-reproducible bakes.",
    )
    parser.add_argument(
        "--height-authority",
        choices=HEIGHT_AUTHORITY_CHOICES,
        default=DEFAULT_HEIGHT_AUTHORITY,
        help="Height source for the generated visual mesh. Use eroded once regenerated assets are in scope.",
    )
    return parser.parse_args()

SURFACES = [
    ("packed_gravel", 1, [0.50, 0.46, 0.36, 1.0]),
    ("packed_dirt", 2, [0.40, 0.23, 0.12, 1.0]),
    ("tall_grass", 3, [0.22, 0.44, 0.15, 1.0]),
    ("mud", 4, [0.12, 0.075, 0.045, 1.0]),
    ("loose_rock", 5, [0.42, 0.40, 0.34, 1.0]),
    ("wet_stone", 6, [0.18, 0.34, 0.38, 1.0]),
    ("wood_plank", 7, [0.50, 0.29, 0.12, 1.0]),
]
SURFACE_INDEX = {name: index for name, index, _color in SURFACES}
SURFACE_COLORS = {name: color for name, _index, color in SURFACES}

REGIONS = [
    ("trailhead_gravel", "packed_gravel", 0.0, 0.75, 2.0, 1.5, 0.0),
    ("log_ramp_apron", "tall_grass", 1.78, 0.62, 1.6, 1.1, 0.0),
    ("main_trail_00", "packed_dirt", 0.0, -2.4, 1.2, 4.8, 0.0),
    ("old_cedar_pad", "packed_dirt", 0.0, -5.15, 2.0, 1.5, 0.0),
    ("meadow_left", "tall_grass", -1.7, -2.5, 2.0, 5.5, 0.0),
    ("meadow_right", "tall_grass", 1.7, -2.0, 2.0, 4.4, 0.0),
    ("culvert_spur", "packed_dirt", -2.2, -1.75, 4.8, 1.6, 0.0),
    ("culvert_mouth_floor", "packed_dirt", -4.35, -3.05, 1.7, 3.0, 0.0),
    ("outcrop_climb", "loose_rock", -1.2, -7.8, 4.6, 4.6, 0.22),
    ("switchback_entry_bridge", "packed_dirt", 0.25, -8.0, 1.8, 1.0, 0.36),
    ("switchback_outer_run", "packed_dirt", 1.55, -6.6, 1.4, 2.6, 0.24),
    ("switchback_lower_landing", "packed_dirt", 0.95, -5.25, 1.8, 1.4, 0.17),
    ("overlook_ridge_pad", "loose_rock", -2.3, -9.1, 3.8, 2.4, 0.36),
    ("bog_approach", "packed_dirt", 1.4, -5.25, 2.0, 1.0, -0.02),
    ("bog_bottom", "mud", 2.8, -5.5, 2.4, 2.4, -0.04),
    ("boardwalk_creek_connector", "mud", 3.9, -4.75, 2.2, 2.6, -0.04),
    ("creek_bank", "mud", 3.2, -6.85, 2.2, 1.9, -0.05),
    ("wet_stone_crossing", "wet_stone", 4.2, -7.35, 3.0, 2.9, -0.01),
    ("boardwalk", "wood_plank", 3.25, -3.35, 1.4, 2.6, 0.03),
]


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


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 0.0
    t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def gaussian(value, center, width):
    delta = (value - center) / max(width, 0.001)
    return math.exp(-delta * delta)


def region_weight(x, z, region):
    _name, _surface, cx, cz, sx, sz, _height = region
    dx = abs(x - cx) - sx * 0.5
    dz = abs(z - cz) - sz * 0.5
    outside = max(dx, dz)
    return 1.0 - smoothstep(-0.05, 0.55, outside)


def terrain_height(x, z):
    return height_authority().height_at(x, z)


def configure_height_authority(
    seed=DEFAULT_TERRAIN_SEED,
    version=DEFAULT_TERRAIN_VERSION,
    mode=DEFAULT_HEIGHT_AUTHORITY,
):
    global _HEIGHT_AUTHORITY
    _HEIGHT_AUTHORITY = TerrainHeightAuthority(seed, version, mode)


def height_authority():
    if _HEIGHT_AUTHORITY is None:
        configure_height_authority()
    return _HEIGHT_AUTHORITY


class TerrainHeightAuthority:
    def __init__(self, seed, version, mode):
        self.seed = int(seed)
        self.version = str(version)
        self.mode = str(mode)
        self._eroded_heightfield = None

    def height_at(self, x, z):
        height = self.base_height_at(x, z) + analytic_landmark_lobes(x, z)
        height = composite_region_height_targets(height, x, z)
        if not self.uses_erosion():
            height += legacy_detail_ripple(x, z)
        return height

    def base_height_at(self, x, z):
        if not self.uses_erosion():
            return TERRAIN_BASE_ELEVATION
        return sample_eroded_heightfield(self.eroded_heightfield(), x, z)

    def eroded_heightfield(self):
        if self._eroded_heightfield is None:
            width, depth = erosion_work_grid()
            kwargs = erosion_build_kwargs(self.seed, self.version)
            self._eroded_heightfield = _build_eroded_heightfield(width, depth, terrain_bounds(), **kwargs)
        return self._eroded_heightfield

    def uses_erosion(self):
        if self.mode == "legacy":
            return False
        if self.mode == "auto":
            return _build_eroded_heightfield is not None and _sample_heightfield is not None
        if self.mode == "eroded":
            if _build_eroded_heightfield is None or _sample_heightfield is None:
                raise RuntimeError("--height-authority eroded requires tools/erosion.py")
            return True
        raise ValueError(f"unknown height authority: {self.mode}")


def erosion_build_kwargs(seed, version):
    kwargs = {}
    if function_accepts_keyword(_build_eroded_heightfield, "seed"):
        kwargs["seed"] = seed
    if function_accepts_keyword(_build_eroded_heightfield, "version"):
        kwargs["version"] = version
    if function_accepts_keyword(_build_eroded_heightfield, "config"):
        config = erosion_config()
        if config is not None:
            kwargs["config"] = config
    return kwargs


def erosion_config():
    config_type = getattr(_erosion_module, "ErosionConfig", None)
    if config_type is None:
        return None
    try:
        return config_type(base_height=TERRAIN_BASE_ELEVATION)
    except TypeError:
        return config_type()


def function_accepts_keyword(function, keyword):
    signature = inspect.signature(function)
    for parameter in signature.parameters.values():
        if parameter.kind == inspect.Parameter.VAR_KEYWORD:
            return True
    return keyword in signature.parameters


def sample_eroded_heightfield(heightfield, x, z):
    if sample_heightfield_accepts_bounds():
        return float(_sample_heightfield(heightfield, terrain_bounds(), x, z))
    return float(_sample_heightfield(heightfield, x, z))


def sample_heightfield_accepts_bounds():
    signature = inspect.signature(_sample_heightfield)
    positional_count = 0
    for parameter in signature.parameters.values():
        if parameter.kind in (inspect.Parameter.POSITIONAL_ONLY, inspect.Parameter.POSITIONAL_OR_KEYWORD):
            positional_count += 1
    return "bounds" in signature.parameters or positional_count >= 4


def terrain_bounds():
    return TERRAIN_DEF.bounds_min_xz, TERRAIN_DEF.bounds_max_xz


def erosion_work_grid():
    span_x = X_MAX - X_MIN
    span_z = Z_MAX - Z_MIN
    if span_x >= span_z:
        depth = EROSION_WORK_GRID_MIN
        width = min(EROSION_WORK_GRID_MAX, max(EROSION_WORK_GRID_MIN, int(round(depth * span_x / span_z))))
    else:
        width = EROSION_WORK_GRID_MIN
        depth = min(EROSION_WORK_GRID_MAX, max(EROSION_WORK_GRID_MIN, int(round(width * span_z / span_x))))
    return width, depth


def analytic_landmark_lobes(x, z):
    height = 0.0
    height += 0.05 * gaussian(x, -4.7, 0.9) * gaussian(z, -2.5, 5.2)
    height += 0.05 * gaussian(x, 4.9, 0.9) * gaussian(z, -3.7, 5.2)
    height += 0.10 * gaussian(z, -10.0, 1.5)
    height += 0.12 * gaussian(x, -2.0, 2.2) * gaussian(z, -8.8, 1.8)
    height += 0.20 * smoothstep(-7.2, -8.7, z) * gaussian(x, -1.3, 2.4)
    height += 0.10 * gaussian(x, 1.4, 1.5) * gaussian(z, -6.1, 2.0)
    height -= 0.07 * gaussian(x, 3.5, 1.8) * gaussian(z, -6.0, 2.0)
    return height


def composite_region_height_targets(height, x, z):
    for region in REGIONS:
        target_height = region[6]
        weight = region_weight(x, z, region)
        height = height * (1.0 - weight * 0.55) + target_height * (weight * 0.55)
    trail_weight = extended_trail_weight(x, z)
    if trail_weight > 0.0:
        trail_target_height = -0.015 + 0.025 * gaussian(z, -34.0, 16.0)
        height = height * (1.0 - trail_weight * 0.45) + trail_target_height * (trail_weight * 0.45)
    return height


def legacy_detail_ripple(x, z):
    return math.sin(x * 3.1 + z * 1.7) * 0.006 + math.sin(x * 1.3 - z * 2.1) * 0.004


def surface_at(x, z):
    best_surface = "tall_grass"
    best_weight = 0.0
    for region in REGIONS:
        weight = region_weight(x, z, region)
        if weight > best_weight:
            best_weight = weight
            best_surface = region[1]
    trail_weight = extended_trail_weight(x, z)
    if trail_weight > 0.55:
        return "packed_dirt"
    if trail_weight > 0.18 and best_weight < 0.35:
        return "packed_dirt"
    return best_surface


def extended_trail_weight(x, z):
    if z >= EXTENDED_TRAIL_START_Z or z <= EXTENDED_TRAIL_END_Z:
        return 0.0
    center_x = extended_trail_center_x(z)
    edge_distance = abs(x - center_x) - EXTENDED_TRAIL_HALF_WIDTH
    lateral_weight = 1.0 - smoothstep(-0.08, EXTENDED_TRAIL_EDGE_BLEND, edge_distance)
    start_fade = smoothstep(EXTENDED_TRAIL_START_Z, EXTENDED_TRAIL_START_Z - 2.4, z)
    end_fade = 1.0 - smoothstep(EXTENDED_TRAIL_END_Z + 4.0, EXTENDED_TRAIL_END_Z, z)
    return max(0.0, min(1.0, lateral_weight * start_fade * end_fade))


def extended_trail_center_x(z):
    distance = EXTENDED_TRAIL_START_Z - z
    return math.sin(distance * 0.16) * 1.55 + math.sin(distance * 0.047 + 0.8) * 0.55


def normalize(vector):
    length = math.sqrt(vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2])
    if length <= 0.000001:
        return (0.0, 1.0, 0.0)
    return (vector[0] / length, vector[1] / length, vector[2] / length)


def subtract(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def build_mesh(tile_index):
    (tile_min_x, tile_min_z), (tile_max_x, tile_max_z) = TERRAIN_DEF.tile_bounds(tile_index)
    vertices = []
    uvs = []
    for z_index in range(GRID_Z):
        z_t = float(z_index) / float(GRID_Z - 1)
        z = tile_min_z + (tile_max_z - tile_min_z) * z_t
        for x_index in range(GRID_X):
            x_t = float(x_index) / float(GRID_X - 1)
            x = tile_min_x + (tile_max_x - tile_min_x) * x_t
            vertices.append((x, terrain_height(x, z), z))
            uvs.append((x_t, 1.0 - z_t))

    indices_by_surface = {name: [] for name, _index, _color in SURFACES}
    for z_index in range(GRID_Z - 1):
        for x_index in range(GRID_X - 1):
            i0 = z_index * GRID_X + x_index
            i1 = i0 + 1
            i2 = i0 + GRID_X
            i3 = i2 + 1
            cx = (vertices[i0][0] + vertices[i3][0]) * 0.5
            cz = (vertices[i0][2] + vertices[i3][2]) * 0.5
            surface = surface_at(cx, cz)
            indices_by_surface[surface].extend([i0, i2, i1, i1, i2, i3])

    normals = [(0.0, 0.0, 0.0) for _vertex in vertices]
    for indices in indices_by_surface.values():
        for index in range(0, len(indices), 3):
            a_index = indices[index]
            b_index = indices[index + 1]
            c_index = indices[index + 2]
            a = vertices[a_index]
            b = vertices[b_index]
            c = vertices[c_index]
            normal = cross(subtract(b, a), subtract(c, a))
            normals[a_index] = add(normals[a_index], normal)
            normals[b_index] = add(normals[b_index], normal)
            normals[c_index] = add(normals[c_index], normal)
    normals = [normalize(normal) for normal in normals]
    return vertices, normals, uvs, indices_by_surface


def pack_vec3(values):
    return b"".join(struct.pack("<fff", value[0], value[1], value[2]) for value in values)


def pack_vec2(values):
    return b"".join(struct.pack("<ff", value[0], value[1]) for value in values)


def pack_indices(indices):
    return b"".join(struct.pack("<H", index) for index in indices)


def bounds(vertices):
    mins = [min(vertex[index] for vertex in vertices) for index in range(3)]
    maxs = [max(vertex[index] for vertex in vertices) for index in range(3)]
    return mins, maxs


def write_glb(path, tile_index):
    vertices, normals, uvs, indices_by_surface = build_mesh(tile_index)
    binary = bytearray()
    heightmesh_name = heightmesh_name_for_tile(tile_index)

    position_data = pack_vec3(vertices)
    normal_data = pack_vec3(normals)
    uv_data = pack_vec2(uvs)
    position_offset = append_aligned(binary, position_data)
    normal_offset = append_aligned(binary, normal_data)
    uv_offset = append_aligned(binary, uv_data)

    buffer_views = [
        {"buffer": 0, "byteOffset": position_offset, "byteLength": len(position_data), "target": 34962},
        {"buffer": 0, "byteOffset": normal_offset, "byteLength": len(normal_data), "target": 34962},
        {"buffer": 0, "byteOffset": uv_offset, "byteLength": len(uv_data), "target": 34962},
    ]
    mins, maxs = bounds(vertices)
    accessors = [
        {
            "bufferView": 0,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(vertices),
            "type": "VEC3",
            "min": mins,
            "max": maxs,
        },
        {
            "bufferView": 1,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(normals),
            "type": "VEC3",
        },
        {
            "bufferView": 2,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(uvs),
            "type": "VEC2",
        },
    ]

    primitives = []
    for material_index, (surface_name, _surface_index, _color) in enumerate(SURFACES):
        indices = indices_by_surface[surface_name]
        if not indices:
            continue
        index_data = pack_indices(indices)
        index_offset = append_aligned(binary, index_data)
        buffer_views.append({"buffer": 0, "byteOffset": index_offset, "byteLength": len(index_data), "target": 34963})
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
        primitives.append(
            {
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": len(accessors) - 1,
                "mode": 4,
                "material": material_index,
            }
        )

    bin_chunk = pad4(bytes(binary), b"\0")
    gltf = {
        "asset": {"version": "2.0", "generator": "Trailhead generate_heightmesh_assets.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": heightmesh_name, "mesh": 0}],
        "meshes": [{"name": heightmesh_name, "primitives": primitives}],
        "materials": [
            {
                "name": "terrain_mat_" + surface_name,
                "pbrMetallicRoughness": {
                    "baseColorFactor": SURFACE_COLORS[surface_name],
                    "roughnessFactor": 1.0,
                    "metallicFactor": 0.0,
                },
            }
            for surface_name, _surface_index, _color in SURFACES
        ],
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


def heightmesh_name_for_tile(tile_index):
    if tile_index == (0, 0):
        return "cedar_hollow_heightmesh"
    return "cedar_hollow_heightmesh_" + tile_coord_label(tile_index[0]) + "_" + tile_coord_label(tile_index[1])


def tile_coord_label(value):
    if value < 0:
        return "neg" + str(abs(value))
    return str(value)


def visual_tile_output_paths(out_dir):
    tile_indices = TERRAIN_DEF.active_tile_indices()
    visual_paths = TERRAIN_DEF.visual_tile_project_paths
    if len(tile_indices) != len(visual_paths):
        raise ValueError("TerrainDef active tile count must match visual tile path count")
    return [(tile_index, out_dir / Path(project_path).name) for tile_index, project_path in zip(tile_indices, visual_paths)]


def write_visual_tile_glbs(out_dir):
    written_paths = []
    for tile_index, path in visual_tile_output_paths(out_dir):
        write_glb(path, tile_index)
        written_paths.append(path)
    return written_paths


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_surface_id_png(path):
    rows = []
    for y in range(SURFACE_MAP_HEIGHT):
        z_t = float(y) / float(SURFACE_MAP_HEIGHT - 1)
        z = Z_MAX + (Z_MIN - Z_MAX) * z_t
        row = bytearray([0])
        for x in range(SURFACE_MAP_WIDTH):
            x_t = float(x) / float(SURFACE_MAP_WIDTH - 1)
            world_x = X_MIN + (X_MAX - X_MIN) * x_t
            surface = surface_at(world_x, z)
            row.append(SURFACE_INDEX[surface])
        rows.append(bytes(row))
    raw = b"".join(rows)
    header = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", SURFACE_MAP_WIDTH, SURFACE_MAP_HEIGHT, 8, 0, 0, 0, 0)
    with path.open("wb") as file:
        file.write(header)
        file.write(png_chunk(b"IHDR", ihdr))
        file.write(png_chunk(b"IDAT", zlib.compress(raw, 9)))
        file.write(png_chunk(b"IEND", b""))


def write_heightmap_collision(path, tile_index=(0, 0), source_project_path=None):
    values = collision_heightmap_values(tile_index, source_project_path)
    width, depth = collision_grid_for_tile(tile_index)
    path.write_text(
        "[gd_resource type=\"HeightMapShape3D\" format=3]\n\n"
        "[resource]\n"
        f"map_width = {width}\n"
        f"map_depth = {depth}\n"
        "map_data = PackedFloat32Array(" + ", ".join(values) + ")\n",
        encoding="utf-8",
    )


def write_heightmap_collision_tiles(collision_out_dir):
    collision_out_dir.mkdir(parents=True, exist_ok=True)
    tile_indices = TERRAIN_DEF.active_tile_indices()
    collision_paths = TERRAIN_DEF.collision_tile_project_paths
    if len(tile_indices) != len(collision_paths):
        raise ValueError("TerrainDef active tile count must match collision tile path count")
    written_paths = []
    for tile_index, source_project_path in zip(tile_indices, collision_paths):
        output_path = collision_out_dir / Path(source_project_path).name
        write_heightmap_collision(output_path, tile_index, source_project_path)
        written_paths.append(output_path)
    return written_paths


def collision_grid_for_tile(_tile_index):
    return COLLISION_GRID_X, COLLISION_GRID_Z


def collision_heightmap_values(tile_index, _source_project_path):
    (tile_min_x, tile_min_z), (tile_max_x, tile_max_z) = TERRAIN_DEF.tile_bounds(tile_index)
    width, depth = collision_grid_for_tile(tile_index)
    values = []
    for z_index in range(depth):
        z_t = float(z_index) / float(depth - 1)
        z = tile_min_z + (tile_max_z - tile_min_z) * z_t
        for x_index in range(width):
            x_t = float(x_index) / float(width - 1)
            x = tile_min_x + (tile_max_x - tile_min_x) * x_t
            values.append(format_float32(terrain_collision_height(x, z)))
    return values


def terrain_collision_height(x, z):
    return terrain_height(x, z)


def format_float32(value):
    float32_value = struct.unpack("<f", struct.pack("<f", float(value)))[0]
    return format(float32_value, ".9g")


def main():
    args = parse_args()
    configure_height_authority(args.terrain_seed, args.terrain_version, args.height_authority)
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    surface_id_path = out_dir / SURFACE_ID_FILENAME
    for glb_path in write_visual_tile_glbs(out_dir):
        print(f"wrote: {glb_path}")
    write_surface_id_png(surface_id_path)
    print(f"wrote: {surface_id_path}")
    if args.collision_out_dir is not None:
        for collision_path in write_heightmap_collision_tiles(args.collision_out_dir):
            print(f"wrote: {collision_path}")


if __name__ == "__main__":
    main()
