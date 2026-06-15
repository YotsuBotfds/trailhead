from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TERRAIN_DEF = ROOT / "data/terrain/cedar_hollow_terrain_def.tres"


@dataclass(frozen=True)
class TerrainDef:
    bounds_min_xz: tuple[float, float]
    bounds_max_xz: tuple[float, float]
    tile_grid: tuple[int, int]
    tile_grid_origin: tuple[int, int]
    tile_size: tuple[float, float]
    tile_indices: tuple[tuple[int, int], ...]
    collision_grid: tuple[int, int]
    visual_grid: tuple[int, int]
    surface_map_size: tuple[int, int]
    surface_id_map_path: str
    collision_tile_paths: tuple[str, ...]
    visual_tile_paths: tuple[str, ...]

    def res_path_to_project_path(self, path: str) -> str:
        if path.startswith("res://"):
            return path.removeprefix("res://")
        return path

    @property
    def surface_id_map_project_path(self) -> str:
        return self.res_path_to_project_path(self.surface_id_map_path)

    @property
    def collision_tile_project_paths(self) -> tuple[str, ...]:
        return tuple(self.res_path_to_project_path(path) for path in self.collision_tile_paths)

    @property
    def visual_tile_project_paths(self) -> tuple[str, ...]:
        return tuple(self.res_path_to_project_path(path) for path in self.visual_tile_paths)

    def active_tile_indices(self) -> tuple[tuple[int, int], ...]:
        if self.tile_indices:
            return self.tile_indices
        origin_x, origin_z = self.tile_grid_origin
        return tuple(
            (tile_x, tile_z)
            for tile_z in range(origin_z, origin_z + self.tile_grid[1])
            for tile_x in range(origin_x, origin_x + self.tile_grid[0])
        )

    def tile_bounds(self, tile_index: tuple[int, int]) -> tuple[tuple[float, float], tuple[float, float]]:
        min_x = self.bounds_min_xz[0] + float(tile_index[0] - self.tile_grid_origin[0]) * self.tile_size[0]
        min_z = self.bounds_min_xz[1] + float(tile_index[1] - self.tile_grid_origin[1]) * self.tile_size[1]
        return (min_x, min_z), (min_x + self.tile_size[0], min_z + self.tile_size[1])


def load_terrain_def(path: Path = DEFAULT_TERRAIN_DEF) -> TerrainDef:
    text = path.read_text(encoding="utf-8")
    return TerrainDef(
        bounds_min_xz=_parse_vector2(_field(text, "bounds_min_xz")),
        bounds_max_xz=_parse_vector2(_field(text, "bounds_max_xz")),
        tile_grid=_parse_vector2i(_field(text, "tile_grid")),
        tile_grid_origin=_parse_vector2i(_optional_field(text, "tile_grid_origin", "Vector2i(0, 0)")),
        tile_size=_parse_vector2(_field(text, "tile_size")),
        tile_indices=_parse_vector2i_array(_field(text, "tile_indices")),
        collision_grid=_parse_vector2i(_field(text, "collision_grid")),
        visual_grid=_parse_vector2i(_field(text, "visual_grid")),
        surface_map_size=_parse_vector2i(_field(text, "surface_map_size")),
        surface_id_map_path=_parse_string(_field(text, "surface_id_map_path")),
        collision_tile_paths=_parse_string_array(_field(text, "collision_tile_paths")),
        visual_tile_paths=_parse_string_array(_field(text, "visual_tile_paths")),
    )


def _field(text: str, name: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\s*=\s*(.+)$", text, flags=re.MULTILINE)
    if match is None:
        raise ValueError(f"missing TerrainDef field: {name}")
    return match.group(1).strip()


def _optional_field(text: str, name: str, default: str) -> str:
    match = re.search(r"^" + re.escape(name) + r"\s*=\s*(.+)$", text, flags=re.MULTILINE)
    if match is None:
        return default
    return match.group(1).strip()


def _parse_vector2(value: str) -> tuple[float, float]:
    match = re.fullmatch(r"Vector2\(([^,]+),\s*([^)]+)\)", value)
    if match is None:
        raise ValueError(f"expected Vector2, got: {value}")
    return float(match.group(1)), float(match.group(2))


def _parse_vector2i(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"Vector2i\(([^,]+),\s*([^)]+)\)", value)
    if match is None:
        raise ValueError(f"expected Vector2i, got: {value}")
    return int(match.group(1)), int(match.group(2))


def _parse_vector2i_array(value: str) -> tuple[tuple[int, int], ...]:
    match = re.fullmatch(r"Array\[Vector2i\]\(\[(.*)\]\)", value)
    if match is None:
        raise ValueError(f"expected Array[Vector2i], got: {value}")
    inner = match.group(1).strip()
    if not inner:
        return tuple()
    return tuple(_parse_vector2i(part.strip()) for part in re.findall(r"Vector2i\([^)]+\)", inner))


def _parse_string(value: str) -> str:
    match = re.fullmatch(r'"([^"]*)"', value)
    if match is None:
        raise ValueError(f"expected string, got: {value}")
    return match.group(1)


def _parse_string_array(value: str) -> tuple[str, ...]:
    match = re.fullmatch(r"Array\[String\]\(\[(.*)\]\)", value)
    if match is None:
        raise ValueError(f"expected Array[String], got: {value}")
    inner = match.group(1).strip()
    if not inner:
        return tuple()
    return tuple(item.group(1) for item in re.finditer(r'"([^"]*)"', inner))
