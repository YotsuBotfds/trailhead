extends RefCounted

# Horizontally-project the vehicle backward facing so the chase rod never tilts with
# vehicle pitch/roll/flip. Hold the last good heading when the car is near-vertical.
static func rod_back(vehicle_basis: Basis, prev_back: Vector3) -> Vector3:
	var flat_back: Vector3 = Vector3(vehicle_basis.z.x, 0.0, vehicle_basis.z.z)
	if flat_back.length() < 0.01:
		if prev_back.length() > 0.01:
			return prev_back.normalized()
		return Vector3(0.0, 0.0, 1.0)
	return flat_back.normalized()
