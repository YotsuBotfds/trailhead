extends Node

signal vehicle_changed_surface(surface_id: StringName)
signal vehicle_flipped_over()
signal vehicle_self_righted()
signal vehicle_recovered_to_trail(from_position: Vector3, to_position: Vector3)

signal world_reached_landmark(landmark_id: StringName)
signal world_recoverable_object_tagged(object_id: StringName)
signal world_photograph_taken(nearest_landmark_id: StringName, sim_tick: int)
signal world_golden_line_matched(segment_id: StringName, sim_tick: int)
signal world_egg_triggered(egg_id: StringName)
signal world_egg_sequence_step(sequence_id: StringName, step_index: int)

signal sim_logbook_entry_written(entry_type: StringName, key: StringName, sim_tick: int)
signal sim_pace_clock_incident(incident_type: StringName, elapsed_ticks: int)
