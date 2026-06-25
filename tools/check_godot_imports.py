#!/usr/bin/env python3
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOTS = (ROOT / "assets" / "models", ROOT / "assets" / "textures")
CHECKED_SUFFIXES = {".glb", ".png", ".jpg", ".jpeg"}
TEXTURE_SUFFIXES = {".png", ".jpg", ".jpeg"}
SURFACE_ID_PNG_NAME = "cedar_hollow_surface_id.png"
GRADE_LUT_PNG_NAME = "zion_splittone_lut.png"
RESIDUE_TEXTURE_DIR = Path("assets/textures/vehicle/residue")
SURFACE_VISUALS_DIRS = (
    Path("assets/textures/surface_visuals/ambientcg"),
    Path("assets/textures/surface_visuals/generated"),
)


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def parse_import_file(path):
    values = {}
    in_metadata = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("["):
            continue
        if in_metadata:
            if line == "}":
                in_metadata = False
                continue
            if ":" in line:
                meta_key, meta_value = line.split(":", 1)
                values["metadata/" + unquote(meta_key.strip())] = unquote(meta_value.strip())
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key == "metadata" and value == "{":
            in_metadata = True
            continue
        values[key] = unquote(value)
    return values


def expected_cache_path(res_path):
    source_hash = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    name = Path(res_path).name
    return "res://.godot/imported/" + name + "-" + source_hash


def imported_cache_paths(values):
    paths = []
    for key, value in values.items():
        if key == "path" or key.startswith("path."):
            paths.append(value)
    return paths


def validate_asset(path):
    rel_path = path.relative_to(ROOT)
    res_path = "res://" + rel_path.as_posix()
    import_path = Path(str(path) + ".import")
    errors = []
    if not import_path.is_file():
        errors.append("missing import metadata: " + str(import_path.relative_to(ROOT)))
        return errors
    values = parse_import_file(import_path)
    source_file = values.get("source_file", "")
    if source_file != res_path:
        errors.append(str(import_path.relative_to(ROOT)) + " source_file expected " + res_path + ", got " + source_file)
    expected_path_prefix = expected_cache_path(res_path)
    imported_paths = imported_cache_paths(values)
    if not any(imported_path.startswith(expected_path_prefix) for imported_path in imported_paths):
        errors.append(str(import_path.relative_to(ROOT)) + " path should use Godot import hash for " + res_path)
    uid = values.get("uid", "")
    if not uid.startswith("uid://"):
        errors.append(str(import_path.relative_to(ROOT)) + " should include a Godot uid")
    suffix = path.suffix.lower()
    if suffix == ".glb":
        validate_glb_import(path, import_path, values, errors)
    if suffix in TEXTURE_SUFFIXES:
        validate_texture_import(path, import_path, values, errors)
    return errors


def validate_glb_import(path, import_path, values, errors):
    label = str(import_path.relative_to(ROOT))
    if values.get("importer", "") != "scene":
        errors.append(label + " importer should be scene for GLB asset")
    if values.get("nodes/root_scale", "") != "1.0":
        errors.append(label + " nodes/root_scale should stay 1.0 for real-meter assets")
    if values.get("nodes/apply_root_scale", "") != "true":
        errors.append(label + " nodes/apply_root_scale should stay true with root_scale=1.0")
    if values.get("nodes/use_name_suffixes", "") != "true":
        errors.append(label + " nodes/use_name_suffixes should stay true for imported node contract checks")
    if values.get("meshes/ensure_tangents", "") != "true":
        errors.append(label + " meshes/ensure_tangents should stay true for normal-mapped render assets")


def validate_texture_import(path, import_path, values, errors):
    label = str(import_path.relative_to(ROOT))
    if path.name == GRADE_LUT_PNG_NAME:
        # Warm/cool color-grade LUT is a legitimate 3D texture (CompressedTexture3D),
        # imported with the 3d_texture importer (a sliced HALD strip), not the 2D
        # texture importer. Layers under FILMIC via Environment.adjustment_color_correction.
        if values.get("importer", "") != "3d_texture":
            errors.append(label + " grade LUT should use the 3d_texture importer")
        return
    if values.get("importer", "") != "texture":
        errors.append(label + " importer should be texture for image asset")
    rel_path = path.relative_to(ROOT)
    if path.name == SURFACE_ID_PNG_NAME:
        validate_surface_id_texture_import(label, values, errors)
        return
    if rel_path.parent in SURFACE_VISUALS_DIRS:
        validate_surface_visual_texture_import(path, label, values, errors)
        return
    if rel_path.parent == RESIDUE_TEXTURE_DIR:
        validate_residue_texture_import(label, values, errors)
        return


def validate_surface_id_texture_import(label, values, errors):
    expected_values = {
        "compress/mode": "0",
        "mipmaps/generate": "false",
        "process/channel_remap/red": "0",
        "process/channel_remap/green": "1",
        "process/channel_remap/blue": "2",
        "process/channel_remap/alpha": "3",
        "process/hdr_as_srgb": "false",
        "detect_3d/compress_to": "1",
    }
    for key, expected_value in expected_values.items():
        actual_value = values.get(key, "")
        if actual_value != expected_value:
            errors.append(label + " " + key + " expected " + expected_value + ", got " + actual_value)


def validate_surface_visual_texture_import(path, label, values, errors):
    expected_values = {
        "metadata/vram_texture": "true",
        "compress/mode": "2",
        "compress/high_quality": "true",
        "mipmaps/generate": "true",
        "mipmaps/limit": "-1",
        "detect_3d/compress_to": "1",
        "compress/normal_map": "1" if "_normal" in path.stem else "0",
    }
    for key, expected_value in expected_values.items():
        actual_value = values.get(key, "")
        if actual_value != expected_value:
            errors.append(label + " " + key + " expected " + expected_value + ", got " + actual_value)
    if "path.bptc" not in values:
        errors.append(label + " should use path.bptc for high-quality VRAM-compressed surface visuals")
    if "s3tc_bptc" not in values.get("metadata/imported_formats", ""):
        errors.append(label + " metadata/imported_formats should include s3tc_bptc")


def validate_residue_texture_import(label, values, errors):
    expected_values = {
        "compress/mode": "0",
        "mipmaps/generate": "false",
        "process/channel_remap/alpha": "3",
        "process/fix_alpha_border": "true",
        "process/premult_alpha": "false",
        "detect_3d/compress_to": "1",
    }
    for key, expected_value in expected_values.items():
        actual_value = values.get(key, "")
        if actual_value != expected_value:
            errors.append(label + " " + key + " expected " + expected_value + ", got " + actual_value)


def main():
    errors = []
    for asset_root in ASSET_ROOTS:
        if not asset_root.exists():
            continue
        for path in sorted(asset_root.rglob("*")):
            if path.suffix.lower() in CHECKED_SUFFIXES:
                errors.extend(validate_asset(path))
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("ok: Godot import metadata present for assets/models and assets/textures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
