extends Node

const ChaseCameraRigScript: GDScript = preload("res://systems/render/chase_camera_rig.gd")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")

# Headless regression guard for the chase-camera stop-lock (Phase 3 of the
# vehicle visual-fixes plan). The vehicle rigid body is forced never-sleeping,
# so even at rest its basis/velocity carry sub-tick jitter; the chase cam hard-
# follows that pose 1:1 and the accel term divides the velocity delta by ~delta
# (~60x noise gain), making the stationary camera visibly shake. The stop-lock
# freezes the camera's pose + accel terms below cam_stop_lock_speed (hysteresis
# via the higher cam_stop_lock_release_speed).
#
# This fixture proves the freeze deterministically: feed the rig a stationary
# vehicle state with deliberate per-tick jitter (position/basis/velocity noise)
# and assert the camera's global_position + look_target + bank/pitch stay
# EXACTLY constant across many update() calls. Without the lock, the jittered
# state would drift the camera every frame.
#
# Run: <godot> --headless --path . res://tools/chase_camera_stop_lock_fixture.tscn
func _ready() -> void:
	var failures: int = 0
	var camera: Camera3D = Camera3D.new()
	add_child(camera)

	var rig: RefCounted = ChaseCameraRigScript.new()
	# Seed the rig with one real update so it initializes (records a pose).
	var seed_state: RefCounted = _stationary_state(Vector3(1.0, 0.05, -3.0), Basis.IDENTITY, Vector3.ZERO)
	rig.update(camera, seed_state, 0.0, 1.0 / 120.0, true, true, 0.0, 0.0)
	var frozen_position: Vector3 = camera.global_position
	var frozen_look: Vector3 = rig.get("look_target_current")
	var frozen_bank: float = float(rig.get("_bank_current_deg"))
	var frozen_pitch: float = float(rig.get("_pitch_current_deg"))

	# Now feed 30 frames of jittered-but-stationary state (speed stays below the
	# lock threshold). The camera pose must NOT move at all.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(30):
		var jitter_pos: Vector3 = Vector3(
			1.0 + rng.randf_range(-0.0005, 0.0005),
			0.05 + rng.randf_range(-0.0002, 0.0002),
			-3.0 + rng.randf_range(-0.0005, 0.0005)
		)
		var jitter_vel: Vector3 = Vector3(rng.randf_range(-0.01, 0.01), 0.0, rng.randf_range(-0.01, 0.01))
		var tiny_yaw: Basis = Basis(Vector3.UP, deg_to_rad(rng.randf_range(-0.3, 0.3)))
		var jitter_state: RefCounted = _stationary_state(jitter_pos, tiny_yaw, jitter_vel)
		rig.update(camera, jitter_state, 0.0, 1.0 / 120.0, true, true, 0.0, 0.0)
		if camera.global_position.distance_to(frozen_position) > 1e-6:
			push_error("stop-lock failed: camera position drifted at frame " + str(i) + " by " + str(camera.global_position.distance_to(frozen_position)))
			failures += 1
			break
		if Vector3(rig.get("look_target_current")).distance_to(frozen_look) > 1e-6:
			push_error("stop-lock failed: look target drifted at frame " + str(i))
			failures += 1
			break
		if absf(float(rig.get("_bank_current_deg")) - frozen_bank) > 1e-6:
			push_error("stop-lock failed: bank drifted at frame " + str(i))
			failures += 1
			break
		if absf(float(rig.get("_pitch_current_deg")) - frozen_pitch) > 1e-6:
			push_error("stop-lock failed: pitch drifted at frame " + str(i))
			failures += 1
			break
	if not bool(rig.get("_stop_locked")):
		push_error("stop-lock failed: rig did not enter _stop_locked state below threshold")
		failures += 1

	# Release: a state above cam_stop_lock_release_speed must unlock and move the
	# camera (snap, not stay frozen).
	var moving_state: RefCounted = _stationary_state(Vector3(5.0, 0.05, -3.0), Basis.IDENTITY, Vector3(2.0, 0.0, 0.0))
	rig.update(camera, moving_state, 0.0, 1.0 / 120.0, true, true, 0.0, 0.0)
	if bool(rig.get("_stop_locked")):
		push_error("stop-lock failed: rig did not release above threshold")
		failures += 1
	if camera.global_position.distance_to(frozen_position) < 0.01:
		push_error("stop-lock failed: camera did not snap to new pose on release")
		failures += 1

	if failures == 0:
		print("chase_camera_stop_lock_fixture: OK")
		get_tree().quit(0)
	else:
		get_tree().quit(int(failures))


func _stationary_state(position: Vector3, basis: Basis, velocity: Vector3) -> RefCounted:
	var state: RefCounted = VehicleStateScript.new()
	state.set("position", position)
	state.set("basis", basis)
	state.set("linear_velocity", velocity)
	state.set("angular_velocity", Vector3.ZERO)
	return state
