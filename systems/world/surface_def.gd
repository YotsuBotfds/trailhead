class_name SurfaceDef
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export_range(0.0, 2.0) var friction: float = 1.0
@export_range(0.0, 2.0) var rolling_drag: float = 0.1
@export_range(0.0, 1.0) var slip: float = 0.0
@export var bog_enabled: bool = false
@export_range(0.0, 1.0) var bog_threshold: float = 0.2
@export_range(0.0, 1.0) var mud_residue: float = 0.0
@export_range(0.0, 1.0) var dust_residue: float = 0.0
@export_range(0.0, 1.0) var wetness_residue: float = 0.0
