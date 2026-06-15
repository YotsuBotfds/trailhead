extends SceneTree

const DEFAULT_OUT_PATH: String = "res://tools/spikes/position_keyed_streaming_determinism/position_keyed_streaming_determinism_results.json"
const RUNNER_SCRIPT_PATH: String = "res://tools/spikes/position_keyed_streaming_determinism/position_keyed_streaming_variant.gd"

var _args: Dictionary[String, Variant] = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	var out_path: String = _arg_string("out", DEFAULT_OUT_PATH)
	var repeat: int = maxi(_arg_int("runs", 3), 1)
	var runner_script: Script = load(RUNNER_SCRIPT_PATH) as Script
	var started_usec: int = Time.get_ticks_usec()

	if runner_script == null:
		push_error("Failed to load runner script: " + RUNNER_SCRIPT_PATH)
		quit(1)
		return

	var variant_names: Array[String] = ["pre_pinned", "streamed", "streamed", "streamed"]
	var variant_workers: Array[int] = [0, 1, 2, 8]
	var variant_records: Array[Variant] = []
	for variant_index in range(variant_names.size()):
		variant_records.append({
			"name": variant_names[variant_index],
			"workers": variant_workers[variant_index]
		})
	var runs: Array[Variant] = []
	for run_index in range(repeat):
		for variant_index in range(variant_names.size()):
			var runner: Node = runner_script.new() as Node
			if runner == null:
				push_error("Failed to instantiate runner script")
				quit(1)
				return
			runner.call("configure", variant_names[variant_index], variant_workers[variant_index], run_index)
			get_root().add_child(runner)
			await runner.sim_completed_run
			var result: Dictionary[String, Variant] = runner.get("final_result") as Dictionary[String, Variant]
			runs.append(result)
			runner.queue_free()
			await physics_frame

	var comparison: Dictionary[String, Variant] = _compare_runs(runs)
	var report: Dictionary[String, Variant] = {
		"spike": "position_keyed_streaming_determinism",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine", "unknown"),
		"physics_ticks_per_second": ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0),
		"inputs": {
			"runs_per_variant": repeat,
			"variants": variant_records
		},
		"comparison": comparison,
		"runs": runs,
		"elapsed_ms": _us_to_ms(Time.get_ticks_usec() - started_usec)
	}
	_write_json(out_path, report)
	_print_summary(out_path, comparison)
	if bool(comparison["passed"]):
		quit(0)
	else:
		quit(1)


func _compare_runs(runs: Array[Variant]) -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var baseline_activation: String = ""
	var baseline_trace: String = ""
	var baseline_label: String = ""
	var activation_signatures: Dictionary[String, String] = {}
	var trace_signatures: Dictionary[String, String] = {}
	var worker_ready_sorted: Dictionary[String, bool] = {}
	var activation_counts: Dictionary[String, int] = {}
	var missed_not_ready: Dictionary[String, int] = {}

	for index in range(runs.size()):
		var run: Dictionary[String, Variant] = runs[index] as Dictionary[String, Variant]
		var label: String = _run_label(run)
		var activation_signature: String = JSON.stringify(run["activation_ticks_sorted"])
		var trace_signature: String = JSON.stringify(_trace_for_comparison(run))
		activation_signatures[label] = activation_signature.sha256_text()
		trace_signatures[label] = trace_signature.sha256_text()
		worker_ready_sorted[label] = bool(run["ready_worker_order_is_cell_sorted"])
		activation_counts[label] = int(run["activation_count"])
		missed_not_ready[label] = int(run["missed_activation_due_not_ready"])

		if index == 0:
			baseline_activation = activation_signature
			baseline_trace = trace_signature
			baseline_label = label
			continue
		if activation_signature != baseline_activation:
			errors.append(label + " activation ticks differ from " + baseline_label)
		if trace_signature != baseline_trace:
			errors.append(label + " raycast trace differs from " + baseline_label)
		if not bool(run["activation_sorted_per_tick"]):
			errors.append(label + " activation order was not sorted within a physics tick")
		if not bool(run["activation_cap_respected"]):
			errors.append(label + " exceeded activation cap")
		if int(run["missed_activation_due_not_ready"]) != 0:
			errors.append(label + " had active cells waiting on worker readiness")

	if runs.size() > 0:
		var first_run: Dictionary[String, Variant] = runs[0] as Dictionary[String, Variant]
		if not bool(first_run["activation_sorted_per_tick"]):
			errors.append(baseline_label + " activation order was not sorted within a physics tick")
		if not bool(first_run["activation_cap_respected"]):
			errors.append(baseline_label + " exceeded activation cap")
		if int(first_run["missed_activation_due_not_ready"]) != 0:
			errors.append(baseline_label + " had active cells waiting on worker readiness")

	return {
		"passed": errors.is_empty(),
		"errors": errors,
		"baseline": baseline_label,
		"activation_signature_sha256": activation_signatures,
		"trace_signature_sha256": trace_signatures,
		"worker_ready_order_is_cell_sorted": worker_ready_sorted,
		"activation_counts": activation_counts,
		"missed_activation_due_not_ready": missed_not_ready
	}


func _run_label(run: Dictionary[String, Variant]) -> String:
	return String(run["variant"]) + "_workers_" + str(int(run["workers"])) + "_run_" + str(int(run["run_index"]))


func _trace_for_comparison(run: Dictionary[String, Variant]) -> Array[Variant]:
	var records: Array[Variant] = []
	if not run.has("trace"):
		return records
	var raw_value: Variant = run["trace"]
	if not (raw_value is Array):
		return records
	var raw_trace: Array[Variant] = raw_value as Array[Variant]
	for item in raw_trace:
		if not (item is Dictionary):
			continue
		var record: Dictionary[Variant, Variant] = item as Dictionary[Variant, Variant]
		records.append({
			"tick": record["tick"],
			"center_cell": record["center_cell"],
			"position_xz": record["position_xz"],
			"expected_cell": record["expected_cell"],
			"expected_height": record["expected_height"],
			"hit": record["hit"],
			"hit_y": record["hit_y"],
			"height_error": record["height_error"]
		})
	return records


func _print_summary(out_path: String, comparison: Dictionary[String, Variant]) -> void:
	print("S3 position-keyed streaming determinism")
	print("  out: " + out_path)
	print("  passed: " + str(bool(comparison["passed"])))
	print("  baseline: " + String(comparison["baseline"]))
	print("  activation signatures: " + JSON.stringify(comparison["activation_signature_sha256"]))
	print("  trace signatures: " + JSON.stringify(comparison["trace_signature_sha256"]))
	if not bool(comparison["passed"]):
		print("  errors: " + JSON.stringify(comparison["errors"]))


func _parse_args(raw: PackedStringArray) -> Dictionary[String, Variant]:
	var parsed: Dictionary[String, Variant] = {}
	for arg in raw:
		var item: String = String(arg)
		if item.begins_with("--") and item.contains("="):
			var parts: PackedStringArray = item.substr(2).split("=", true, 1)
			if parts.size() == 2:
				parsed[parts[0]] = parts[1]
	return parsed


func _arg_string(key: String, default_value: String) -> String:
	if not _args.has(key):
		return default_value
	return String(_args[key])


func _arg_int(key: String, default_value: int) -> int:
	if not _args.has(key):
		return default_value
	return int(_args[key])


func _write_json(path: String, data: Dictionary[String, Variant]) -> void:
	var global_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var parent_dir: String = global_path.get_base_dir()
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
	if dir_error != OK:
		push_error("Failed to create output directory " + parent_dir + ": " + error_string(dir_error))
		return
	var file: FileAccess = FileAccess.open(global_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open output path: " + global_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	file.close()


func _us_to_ms(value_us: int) -> float:
	return float(value_us) / 1000.0
