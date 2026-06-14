class_name VehicleContaminationState
extends RefCounted

var mud: float = 0.0
var dust: float = 0.0
var wetness: float = 0.0


func reset() -> void:
	mud = 0.0
	dust = 0.0
	wetness = 0.0


func set_values(mud_value: float, dust_value: float, wetness_value: float) -> void:
	mud = clampf(mud_value, 0.0, 1.0)
	dust = clampf(dust_value, 0.0, 1.0)
	wetness = clampf(wetness_value, 0.0, 1.0)


func as_dictionary() -> Dictionary:
	return {
		"mud": mud,
		"dust": dust,
		"wetness": wetness
	}
