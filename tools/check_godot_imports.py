#!/usr/bin/env python3
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "models"
CHECKED_SUFFIXES = {".glb", ".png"}


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def parse_import_file(path):
    values = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("[") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = unquote(value)
    return values


def expected_cache_path(res_path):
    source_hash = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    name = Path(res_path).name
    return "res://.godot/imported/" + name + "-" + source_hash


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
    imported_path = values.get("path", "")
    if not imported_path.startswith(expected_cache_path(res_path)):
        errors.append(str(import_path.relative_to(ROOT)) + " path should use Godot import hash for " + res_path)
    uid = values.get("uid", "")
    if not uid.startswith("uid://"):
        errors.append(str(import_path.relative_to(ROOT)) + " should include a Godot uid")
    return errors


def main():
    errors = []
    for path in sorted(ASSET_ROOT.rglob("*")):
        if path.suffix in CHECKED_SUFFIXES:
            errors.extend(validate_asset(path))
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("ok: Godot import metadata present for assets/models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
