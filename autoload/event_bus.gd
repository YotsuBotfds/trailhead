extends Node

signal vehicle_changed_surface(surface_id: StringName)
signal vehicle_flipped_over()
signal vehicle_self_righted()

signal world_reached_landmark(landmark_id: StringName)

signal sim_started_run(run_id: String)
signal sim_completed_run(run_id: String, passed: bool)

