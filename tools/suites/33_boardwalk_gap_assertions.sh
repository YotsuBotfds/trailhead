python3 - "$out_dir/cedar_hollow_boardwalk_end.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
errors = []
try:
    data = json.loads(path.read_text())
except OSError as exc:
    print(f"fail: {path}")
    print(f"- missing or unreadable input: {exc}")
    sys.exit(1)
except json.JSONDecodeError as exc:
    print(f"fail: {path}")
    print(f"- bad JSON at line {exc.lineno} column {exc.colno}: {exc.msg}")
    sys.exit(1)

if data.get("result") != "pass":
    errors.append(f"expected result pass, got {data.get('result')}")
predicates = data.get("predicates", {})
if not isinstance(predicates, dict) or not predicates.get("never_stuck", False):
    errors.append("boardwalk traverse did not keep never_stuck true")

telemetry = data.get("telemetry", [])
if not isinstance(telemetry, list):
    telemetry = []
    errors.append("telemetry is not an array")

boardwalk_rows = []
for row in telemetry:
    if not isinstance(row, dict):
        continue
    wheel_surfaces = row.get("wheel_surface", [])
    if not isinstance(wheel_surfaces, list):
        continue
    wood_wheels = sum(1 for surface_id in wheel_surfaces if surface_id == "wood_plank")
    if wood_wheels >= 3:
        boardwalk_rows.append(row)

if len(boardwalk_rows) < 4:
    errors.append(f"expected at least 4 stable boardwalk contact rows, got {len(boardwalk_rows)}")
else:
    y_values = []
    for row in boardwalk_rows:
        position = row.get("position", [])
        if isinstance(position, list) and len(position) >= 2:
            y_values.append(float(position[1]))
        if int(row.get("wheel_contact_count", 0)) < 3:
            errors.append(f"tick {row.get('tick')} had fewer than 3 wheel contacts on boardwalk")
    if y_values:
        min_y = min(y_values)
        max_y = max(y_values)
        y_span = max_y - min_y
        if min_y < 0.04:
            errors.append(f"boardwalk Y dipped to {min_y:.3f} m, below 0.040 m")
        if y_span > 0.08:
            errors.append(f"boardwalk Y span {y_span:.3f} m exceeded 0.080 m")
    else:
        errors.append("stable boardwalk contact rows had no numeric Y positions")

if errors:
    print(f"fail: {path}")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)
print(f"ok: {path} boardwalk gap traversal stayed supported")
PY
