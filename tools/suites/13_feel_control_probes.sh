run_sim "$out_dir/standstill_yaw_rate.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=standstill_yaw_rate \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=320 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/standstill_yaw_rate.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=max_abs_yaw_rate:0.06 \
	--metric-max=max_abs_yaw_rate:0.27

run_sim "$out_dir/steering_speed_ramp.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=steering_speed_ramp \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/steering_speed_ramp.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=steering_speed_low_sample_ticks:6 \
	--metric-min=steering_speed_mid_sample_ticks:6 \
	--metric-min=steering_speed_high_sample_ticks:6 \
	--metric-min=steering_speed_high_max_abs_yaw_rate:0.30

run_sim "$out_dir/reverse_steer_right.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=reverse_steer_right \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/reverse_steer_right.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=max_reverse_distance:0.35 \
	--metric-min=final_control_right_displacement:0.04

run_sim "$out_dir/offtrail_escape_tall_grass.json" \
	--scene=offtrail_escape \
	--controller=scripted \
	--scenario=offtrail_escape \
	--spawn=offtrail_tall_grass \
	--seed=12345 \
	--max-ticks=340 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/offtrail_escape_tall_grass.json" \
	--predicate=scenario_passed \
	--surface=tall_grass:40 \
	--metric-min=max_initial_forward_displacement:0.55

run_sim "$out_dir/offtrail_escape_loose_rock.json" \
	--scene=offtrail_escape \
	--controller=scripted \
	--scenario=offtrail_escape \
	--spawn=offtrail_loose_rock \
	--seed=12345 \
	--max-ticks=340 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/offtrail_escape_loose_rock.json" \
	--predicate=scenario_passed \
	--surface=loose_rock:40 \
	--metric-min=max_initial_forward_displacement:0.55

run_sim "$out_dir/recover_to_trail.json" \
	--scene=recovery_trap \
	--controller=scripted \
	--scenario=recover_to_trail \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/recover_to_trail.json" \
	--predicate=scenario_passed \
	--predicate=event_bus_contract \
	--surface=packed_dirt:40 \
	--metric-min=recovered_to_trail_event_count:1 \
	--metric-min=max_recovery_displacement:0.025

run_sim "$out_dir/hill_hold_grade.json" \
	--scene=hill_hold_probe \
	--controller=scripted \
	--scenario=hill_hold \
	--spawn=hill_hold_grade \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/hill_hold_grade.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-max=max_flat_displacement_from_initial:0.04

run_sim "$out_dir/hill_hold_steep.json" \
	--scene=hill_hold_probe \
	--controller=scripted \
	--scenario=hill_hold \
	--spawn=hill_hold_steep \
	--seed=12345 \
	--max-ticks=420 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/hill_hold_steep.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=final_flat_displacement_from_initial:0.08 \
	--metric-max=final_flat_displacement_from_initial:1.6

run_sim "$out_dir/lateral_slide.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=lateral_slide \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=440 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/lateral_slide.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=max_abs_lateral_speed:0.18 \
	--metric-max=final_abs_lateral_speed:0.08

run_sim "$out_dir/suspension_drop.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=suspension_drop \
	--spawn=suspension_drop \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/suspension_drop.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_speed:2.0 \
	--metric-max=post_settle_y_amplitude:0.02 \
	--metric-max=max_post_settle_vertical_speed:0.08

run_sim "$out_dir/resting_ride_height.json" \
	--scene=flat_plane \
	--controller=scripted \
	--scenario=resting_ride_height \
	--spawn=flat_spawn \
	--seed=12345 \
	--max-ticks=460 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/resting_ride_height.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=resting_ride_height_sample_ticks:80 \
	--metric-min=resting_ride_height_all_contact_ticks:80 \
	--metric-min=resting_ride_height_min_y:0.047 \
	--metric-max=resting_ride_height_max_y:0.062
# Rest-height band shifted up ~7.65 mm vs the prior [0.040, 0.055] to track the
# calibrated wheel_radius (0.03 -> 0.03765, the real GLB wheel_tire radius). The
# buggy now sits at its correct ride height instead of 7.65 mm low; the tolerance
# window (15 mm) is unchanged, only its center moved. See Phase 1 of the vehicle
# visual-fixes plan.

airborne_brake_control_replay="$out_dir/airborne_brake_control_replay.json"
airborne_brake_probe_replay="$out_dir/airborne_brake_probe_replay.json"
python3 - "$airborne_brake_control_replay" "$airborne_brake_probe_replay" <<'PY'
import json
import sys
from pathlib import Path

control_path = Path(sys.argv[1])
probe_path = Path(sys.argv[2])
brake_start_tick = 8
brake_end_tick = 28
drive_start_tick = 60
total_ticks = 420


def input_rows(apply_airborne_brake):
    rows = []
    for tick in range(total_ticks):
        row = {
            "throttle": 0.0,
            "steer": 0.0,
            "brake": 0.0,
            "ebrake": False,
            "self_right": False,
        }
        if apply_airborne_brake and brake_start_tick <= tick < brake_end_tick:
            row["brake"] = 1.0
        elif tick >= drive_start_tick:
            row["throttle"] = 1.0
        rows.append(row)
    return rows


base = {
    "format": "trailhead_replay_v1",
    "ticks": total_ticks,
    "tolerances": {"ticks": total_ticks},
}
control = dict(base)
control["name"] = "airborne_brake_control"
control["inputs"] = input_rows(False)
probe = dict(base)
probe["name"] = "airborne_brake_probe"
probe["inputs"] = input_rows(True)
control_path.write_text(json.dumps(control, indent="\t") + "\n")
probe_path.write_text(json.dumps(probe, indent="\t") + "\n")
PY

run_sim "$out_dir/airborne_brake_control.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay="$airborne_brake_control_replay" \
	--spawn=suspension_drop \
	--target=0,0,-3 \
	--target-radius=0.45 \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/airborne_brake_control.json" \
	--surface=packed_dirt:40 \
	--metric-min=max_speed:2.0

run_sim "$out_dir/airborne_brake_probe.json" \
	--scene=flat_plane \
	--controller=replay \
	--replay="$airborne_brake_probe_replay" \
	--spawn=suspension_drop \
	--target=0,0,-3 \
	--target-radius=0.45 \
	--seed=12345 \
	--max-ticks=520 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/airborne_brake_probe.json" \
	--surface=packed_dirt:40 \
	--metric-min=max_speed:2.0

python3 - "$out_dir/airborne_brake_control.json" "$out_dir/airborne_brake_probe.json" <<'PY'
import json
import sys
from pathlib import Path

control = json.loads(Path(sys.argv[1]).read_text())
probe = json.loads(Path(sys.argv[2]).read_text())
control_rows = {int(row.get("tick", -1)): row for row in control.get("telemetry", [])}
samples = []
errors = []
epsilon = 0.0005

for row in probe.get("telemetry", []):
    tick = int(row.get("tick", -1))
    input_row = row.get("input", {})
    if float(input_row.get("brake", 0.0)) < 0.99 or bool(row.get("on_ground", True)):
        continue
    control_row = control_rows.get(tick)
    if control_row is None or bool(control_row.get("on_ground", True)):
        continue
    probe_speed = float(row.get("speed", 0.0))
    control_speed = float(control_row.get("speed", 0.0))
    delta = probe_speed - control_speed
    samples.append((tick, delta))
    if delta < -epsilon:
        errors.append(
            f"tick {tick}: airborne brake speed {probe_speed:.6f} below control {control_speed:.6f}"
        )

if len(samples) < 8:
    errors.append(f"expected at least 8 airborne brake samples, saw {len(samples)}")

if errors:
    print("fail: airborne brake invariant")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print(f"ok: airborne brake invariant ({len(samples)} samples)")
PY

run_sim "$out_dir/roll_stability.json" \
	--scene=roll_stability_probe \
	--controller=scripted \
	--scenario=roll_stability \
	--spawn=roll_stability_side_slope \
	--seed=12345 \
	--max-ticks=360 \
	--stuck-window=120 \
	--stuck-min-progress=0.05
assert_metrics "$out_dir/roll_stability.json" \
	--predicate=scenario_passed \
	--surface=packed_dirt:40 \
	--metric-min=contact_normal_sample_ticks:80 \
	--metric-min=max_contact_normal_tilt_deg:16.0 \
	--metric-min=max_initial_forward_displacement:1.2 \
	--metric-max=max_abs_roll_deg:35.0
