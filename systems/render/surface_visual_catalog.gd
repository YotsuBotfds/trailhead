class_name SurfaceVisualCatalog
extends Resource

@export var visual_defs: Array[Resource] = []
@export var fallback_surface_id: StringName = &"packed_dirt"


func validate(known_surface_ids: Array[StringName] = []) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var seen_visual_ids: Array[StringName] = []
	var default_surface_ids: Array[StringName] = []
	for i in range(visual_defs.size()):
		var visual_def: Resource = visual_defs[i]
		var label: String = "surface visual #" + str(i)
		if visual_def == null:
			errors.append(label + " is null")
			continue
		var visual_id: StringName = visual_def.get("id")
		var surface_id: StringName = visual_def.get("surface_id")
		var is_default: bool = bool(visual_def.get("default_for_surface"))
		for error in visual_def.call("validate", label):
			errors.append(error)
		if seen_visual_ids.has(visual_id):
			errors.append("duplicate surface visual id: " + String(visual_id))
		seen_visual_ids.append(visual_id)
		if known_surface_ids.size() > 0 and not known_surface_ids.has(surface_id):
			errors.append(String(visual_id) + " references unknown SurfaceDef: " + String(surface_id))
		if is_default:
			if default_surface_ids.has(surface_id):
				errors.append("multiple default surface visuals for SurfaceDef: " + String(surface_id))
			default_surface_ids.append(surface_id)
	if fallback_surface_id == &"":
		errors.append("fallback_surface_id is empty")
	elif known_surface_ids.size() > 0 and not known_surface_ids.has(fallback_surface_id):
		errors.append("fallback_surface_id references unknown SurfaceDef: " + String(fallback_surface_id))
	if known_surface_ids.size() > 0:
		for surface_id in known_surface_ids:
			if not default_surface_ids.has(surface_id):
				errors.append("missing default surface visual for SurfaceDef: " + String(surface_id))
	return errors


func supported_surface_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for visual_def in visual_defs:
		if visual_def == null:
			continue
		var surface_id: StringName = visual_def.get("surface_id")
		if bool(visual_def.get("default_for_surface")) and not ids.has(surface_id):
			ids.append(surface_id)
	return ids


func surface_ids_with_visual_variants() -> Array[StringName]:
	var ids: Array[StringName] = []
	for visual_def in visual_defs:
		if visual_def == null:
			continue
		var surface_id: StringName = visual_def.get("surface_id")
		var visual_count: int = 0
		for candidate in visual_defs:
			if candidate != null and StringName(candidate.get("surface_id")) == surface_id:
				visual_count += 1
		if visual_count > 1 and not ids.has(surface_id):
			ids.append(surface_id)
	return ids


func default_visual_for_surface_id(surface_id: StringName) -> Resource:
	var visual_def: Resource = _default_visual_for_surface_id(surface_id)
	if visual_def != null:
		return visual_def
	if surface_id != fallback_surface_id:
		return _default_visual_for_surface_id(fallback_surface_id)
	return null


func tire_audio_gain_for(surface_id: StringName) -> float:
	var visual_def: Resource = default_visual_for_surface_id(surface_id)
	if visual_def == null:
		return 1.0
	return float(visual_def.get("tire_audio_gain"))


func tire_audio_pitch_for(surface_id: StringName) -> float:
	var visual_def: Resource = default_visual_for_surface_id(surface_id)
	if visual_def == null:
		return 1.0
	return float(visual_def.get("tire_audio_pitch"))


func emits_plank_knock_for(surface_id: StringName) -> bool:
	var visual_def: Resource = default_visual_for_surface_id(surface_id)
	if visual_def == null:
		return false
	return bool(visual_def.get("emits_plank_knock"))


func _default_visual_for_surface_id(surface_id: StringName) -> Resource:
	for visual_def in visual_defs:
		if visual_def != null and StringName(visual_def.get("surface_id")) == surface_id and bool(visual_def.get("default_for_surface")):
			return visual_def
	return null
