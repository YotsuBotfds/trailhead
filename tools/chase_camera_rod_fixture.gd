extends SceneTree

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

# Headless regression guard for FX-25: the chase-camera rod must stay horizontal
# (and unit-length) under any vehicle pitch/roll/flip, so a seam bump cannot swing
# the camera. Run: <godot> --headless --path . --script res://tools/chase_camera_rod_fixture.gd
func _initialize() -> void:
	var failures: int = 0
	var prev_back: Vector3 = Vector3(0.0, 0.0, 1.0)
	var cases: Array = [
		Basis.IDENTITY,
		Basis(Vector3.RIGHT, deg_to_rad(45.0)),
		Basis(Vector3.RIGHT, deg_to_rad(180.0)),
		Basis(Vector3.FORWARD, deg_to_rad(90.0)),
	]
	for basis in cases:
		var back: Vector3 = ChaseCameraMath.rod_back(basis, prev_back)
		if absf(back.y) > 0.0001:
			push_error("rod not horizontal y=" + str(back.y))
			failures += 1
		if absf(back.length() - 1.0) > 0.0001:
			push_error("rod not unit len=" + str(back.length()))
			failures += 1
		prev_back = back
	var vertical: Vector3 = ChaseCameraMath.rod_back(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0.0, 0.0, 1.0))
	if absf(vertical.y) > 0.0001:
		push_error("vertical rod not horizontal y=" + str(vertical.y))
		failures += 1
	if failures == 0:
		print("chase_camera_rod_fixture: OK")
		quit(0)
	else:
		quit(1)
