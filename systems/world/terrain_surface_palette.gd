class_name TerrainSurfacePalette
extends Resource

@export_file("*.png") var image_path: String = ""
@export var id_values: Array[int] = []
@export var surface_ids: Array[StringName] = []


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if image_path.is_empty():
		errors.append("image_path is empty")
	if id_values.size() != surface_ids.size():
		errors.append("id_values and surface_ids must have the same length")
	var seen_ids: Array[int] = []
	for i in range(id_values.size()):
		var id_value: int = id_values[i]
		if id_value < 0 or id_value > 255:
			errors.append("surface ID value out of 8-bit PNG range: " + str(id_value))
		if seen_ids.has(id_value):
			errors.append("duplicate surface ID value: " + str(id_value))
		seen_ids.append(id_value)
		if i >= surface_ids.size():
			continue
		if surface_ids[i] == &"":
			errors.append("empty surface id for value: " + str(id_value))
	return errors


func has_surface_id_value(id_value: int) -> bool:
	return _index_for_value(id_value) != -1


func surface_id_for(id_value: int, fallback: StringName = &"") -> StringName:
	var index: int = _index_for_value(id_value)
	if index == -1 or index >= surface_ids.size():
		return fallback
	return surface_ids[index]


func _index_for_value(id_value: int) -> int:
	for i in range(id_values.size()):
		if id_values[i] == id_value:
			return i
	return -1
