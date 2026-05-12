extends Node

var _data:            Dictionary = {}
var _sim_speed:       float      = 1.0
var _t_start_wall:    float      = 0.0
var _loaded:          bool       = false

func _ready() -> void:
	_t_start_wall = Time.get_ticks_msec() / 1000.0
	_load_results()

func _load_results() -> void:
	var path := ProjectSettings.globalize_path("res://") + "solver_results.json"
	if not FileAccess.file_exists(path):
		push_warning("SolverBridge: solver_results.json not found at " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SolverBridge: cannot open " + path)
		return
	var json_text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_warning("SolverBridge: JSON parse error: " + json.get_error_message())
		return
	_data   = json.get_data()
	_loaded = true
	print("[SolverBridge] loaded: orbit=%d pts, traj=%d pts (apogee %.0f m), access=%d wins" % [
		int(_data.get("point_count", 0)),
		int(_data.get("trajectory_point_count", 0)),
		float(_data.get("trajectory_apogee_m", 0.0)),
		(_data.get("access_windows", []) as Array).size()
	])

# ── Bridge API ─────────────────────────────────────────────────────────────────

func has_new_data(last_frame_id: int) -> bool:
	return _loaded and last_frame_id < 1

func get_frame_id() -> int:
	return 1 if _loaded else 0

func get_point_count() -> int:
	return int(_data.get("point_count", 0))

func copy_positions_to(arr: PackedVector3Array, count: int) -> void:
	if not _loaded:
		return
	var flat: Array = _data.get("positions_flat", [])
	var n := mini(count, flat.size() / 3)
	for i in n:
		arr[i] = Vector3(float(flat[i * 3]), float(flat[i * 3 + 1]), float(flat[i * 3 + 2])) / 1000.0

func get_orbit_start_t_s() -> float:
	return 0.0

func get_orbit_step_s() -> float:
	return float(_data.get("orbit_step_s", 10.0))

func get_mission_summary() -> Dictionary:
	if not _loaded:
		return {}
	return {
		"period_s":        float(_data.get("orbit_period_s",   0.0)),
		"altitude_km":     float(_data.get("altitude_km",      0.0)),
		"inclination_deg": float(_data.get("inclination_deg",  0.0)),
	}

func get_eclipse_result() -> Dictionary:
	if not _loaded:
		return {}
	var starts := PackedFloat64Array(_data.get("eclipse_period_starts", []) as Array)
	var ends   := PackedFloat64Array(_data.get("eclipse_period_ends",   []) as Array)
	return {
		"fraction":      float(_data.get("eclipse_fraction",  0.0)),
		"n_periods":     int(_data.get("eclipse_n_periods",   0)),
		"period_starts": starts,
		"period_ends":   ends,
	}

func get_access_windows() -> Array:
	if not _loaded:
		return []
	return _data.get("access_windows", []) as Array

func get_sim_time_s() -> float:
	return (Time.get_ticks_msec() / 1000.0 - _t_start_wall) * _sim_speed

func set_sim_speed(speed: float) -> void:
	var cur_t := get_sim_time_s()
	_sim_speed = speed
	if _sim_speed > 0.0:
		_t_start_wall = Time.get_ticks_msec() / 1000.0 - cur_t / _sim_speed

func compute_hohmann(r1_km: float, r2_km: float) -> Dictionary:
	const MU := 398600.4418
	if r1_km <= 0.0 or r2_km <= 0.0:
		return {}
	var a_t := (r1_km + r2_km) * 0.5
	var v1  := sqrt(MU / r1_km)
	var v2  := sqrt(MU / r2_km)
	var vp  := sqrt(MU * (2.0 / r1_km - 1.0 / a_t))
	var va  := sqrt(MU * (2.0 / r2_km - 1.0 / a_t))
	return {
		"dv1_kms": vp - v1,
		"dv2_kms": v2 - va,
		"tof_s":   PI * sqrt(a_t * a_t * a_t / MU),
	}

# ── Trajectory API ─────────────────────────────────────────────────────────────

func get_trajectory_point_count() -> int:
	return int(_data.get("trajectory_point_count", 0))

func get_trajectory_apogee_m() -> float:
	return float(_data.get("trajectory_apogee_m", 0.0))

# Fills arr with ENU positions converted to Godot Y-up:
#   Vector3(East, Up, -North)  — .y gives altitude in metres.
func copy_trajectory_positions_to(arr: PackedVector3Array, count: int) -> void:
	if not _loaded:
		return
	var flat: Array = _data.get("trajectory_positions_flat", [])
	var n := mini(count, flat.size() / 3)
	for i in n:
		arr[i] = Vector3(
			float(flat[i * 3]),
			float(flat[i * 3 + 2]),   # ENU Up  → Godot Y
			-float(flat[i * 3 + 1])   # ENU North → Godot -Z
		)

func get_trajectory_times() -> PackedFloat32Array:
	if not _loaded:
		return PackedFloat32Array()
	return PackedFloat32Array(_data.get("trajectory_times", []) as Array)

func export_report_json(user_path: String) -> void:
	if not _loaded:
		push_warning("SolverBridge: no data to export")
		return
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		push_warning("SolverBridge: cannot write " + user_path)
		return
	f.store_string(JSON.stringify(_data, "  "))
	f.close()
