extends RefCounted

const AXIS_LENGTH_MIN: float = 0.01
const UPRIGHT_DOT_MIN: float = 0.15
const BACK_WORLD_UP_DOT_MAX: float = 0.98
const LOOK_UP_DOT_MAX: float = 0.98

# Use the vehicle's full backward axis while it is a stable camera mount. When the
# vehicle is near-vertical/flipped, hold the last safe rod to avoid a flip/spin.
static func rod_back(vehicle_basis: Basis, prev_back: Vector3) -> Vector3:
	var vehicle_back: Vector3 = vehicle_basis.z
	var vehicle_up: Vector3 = vehicle_basis.y
	if not _mount_axes_are_stable(vehicle_back, vehicle_up):
		return _safe_back(prev_back)
	return vehicle_back.normalized()


static func rod_up(vehicle_basis: Basis, back: Vector3, prev_up: Vector3) -> Vector3:
	var vehicle_back: Vector3 = vehicle_basis.z
	var vehicle_up: Vector3 = vehicle_basis.y
	var safe_back: Vector3 = _safe_back(back)
	if not _mount_axes_are_stable(vehicle_back, vehicle_up):
		return _safe_up_for_back(safe_back, prev_up)
	var up: Vector3 = vehicle_up.normalized()
	if absf(up.dot(safe_back)) > LOOK_UP_DOT_MAX:
		return _safe_up_for_back(safe_back, prev_up)
	return up


static func _mount_axes_are_stable(vehicle_back: Vector3, vehicle_up: Vector3) -> bool:
	if vehicle_back.length() < AXIS_LENGTH_MIN or vehicle_up.length() < AXIS_LENGTH_MIN:
		return false
	var back: Vector3 = vehicle_back.normalized()
	var up: Vector3 = vehicle_up.normalized()
	if up.dot(Vector3.UP) < UPRIGHT_DOT_MIN:
		return false
	if absf(back.dot(Vector3.UP)) > BACK_WORLD_UP_DOT_MAX:
		return false
	if absf(back.dot(up)) > LOOK_UP_DOT_MAX:
		return false
	return true


static func _safe_back(prev_back: Vector3) -> Vector3:
	if prev_back.length() > AXIS_LENGTH_MIN:
		return prev_back.normalized()
	return Vector3(0.0, 0.0, 1.0)


static func _safe_up_for_back(back: Vector3, prev_up: Vector3) -> Vector3:
	var projected_prev_up: Vector3 = prev_up - back * prev_up.dot(back)
	if projected_prev_up.length() > AXIS_LENGTH_MIN:
		return projected_prev_up.normalized()
	var projected_world_up: Vector3 = Vector3.UP - back * Vector3.UP.dot(back)
	if projected_world_up.length() > AXIS_LENGTH_MIN:
		return projected_world_up.normalized()
	return Vector3.RIGHT
