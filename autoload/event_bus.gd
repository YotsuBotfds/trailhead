extends Node

signal vehicle_changed_surface(surface_id: StringName)
signal vehicle_flipped_over()
signal vehicle_self_righted()
signal vehicle_recovered_to_trail(from_position: Vector3, to_position: Vector3)

signal world_reached_landmark(landmark_id: StringName)
