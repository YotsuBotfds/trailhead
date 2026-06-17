extends SceneTree

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

# Headless regression guard for FX-25/FX-31: the chase-camera rod follows the
# stable vehicle mount axes, but holds the last safe axes near vertical/flipped
# poses so a seam bump cannot swing the camera into a flip/spin.
# Run: <godot> --headless --path . --script res://tools/chase_camera_rod_fixture.gd
func _initialize() -> void:
	var failures: int = 0
	var prev_back: Vector3 = Vector3(0.0, 0.0, 1.0)
	var prev_up: Vector3 = Vector3.UP
	var stable_cases: Array = [
		Basis.IDENTITY,
		Basis(Vector3.RIGHT, deg_to_rad(45.0)),
		Basis(Vector3.FORWARD, deg_to_rad(35.0)),
	]
	for basis in stable_cases:
		var back: Vector3 = ChaseCameraMath.rod_back(basis, prev_back)
		var up: Vector3 = ChaseCameraMath.rod_up(basis, back, prev_up)
		var expected_back: Vector3 = basis.z.normalized()
		var expected_up: Vector3 = basis.y.normalized()
		if back.distance_to(expected_back) > 0.0001:
			push_error("rod did not follow vehicle back, got=" + str(back) + " expected=" + str(expected_back))
			failures += 1
		if absf(back.length() - 1.0) > 0.0001:
			push_error("rod not unit len=" + str(back.length()))
			failures += 1
		if up.distance_to(expected_up) > 0.0001:
			push_error("up did not follow vehicle up, got=" + str(up) + " expected=" + str(expected_up))
			failures += 1
		if absf(up.length() - 1.0) > 0.0001:
			push_error("up not unit len=" + str(up.length()))
			failures += 1
		if absf(back.dot(up)) > 0.0001:
			push_error("rod/up not orthogonal dot=" + str(back.dot(up)))
			failures += 1
		prev_back = back
		prev_up = up
	var hold_back: Vector3 = Vector3(0.0, -0.25, 0.9682458).normalized()
	var hold_up: Vector3 = Vector3(0.0, 0.9682458, 0.25).normalized()
	var vertical_back: Vector3 = ChaseCameraMath.rod_back(Basis(Vector3.RIGHT, deg_to_rad(90.0)), hold_back)
	var vertical_up: Vector3 = ChaseCameraMath.rod_up(Basis(Vector3.RIGHT, deg_to_rad(90.0)), vertical_back, hold_up)
	if vertical_back.distance_to(hold_back) > 0.0001:
		push_error("near-vertical rod did not hold previous back, got=" + str(vertical_back))
		failures += 1
	if vertical_up.distance_to(hold_up) > 0.0001:
		push_error("near-vertical up did not hold stable up, got=" + str(vertical_up))
		failures += 1
	var flipped_back: Vector3 = ChaseCameraMath.rod_back(Basis(Vector3.RIGHT, deg_to_rad(180.0)), hold_back)
	var flipped_up: Vector3 = ChaseCameraMath.rod_up(Basis(Vector3.RIGHT, deg_to_rad(180.0)), flipped_back, hold_up)
	if flipped_back.distance_to(hold_back) > 0.0001:
		push_error("flipped rod did not hold previous back, got=" + str(flipped_back))
		failures += 1
	if flipped_up.distance_to(hold_up) > 0.0001:
		push_error("flipped up did not hold stable up, got=" + str(flipped_up))
		failures += 1
	if absf(flipped_back.dot(flipped_up)) > 0.0001:
		push_error("flipped hold axes not orthogonal dot=" + str(flipped_back.dot(flipped_up)))
		failures += 1
	if failures == 0:
		print("chase_camera_rod_fixture: OK")
		quit(0)
	else:
		quit(1)
