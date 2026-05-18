class_name MissionParamsIO

const _FILENAME := "mission_params.json"

static func _json_path() -> String:
	return ProjectSettings.globalize_path("res://") + _FILENAME

static func load_params() -> Dictionary:
	var path := _json_path()
	if not FileAccess.file_exists(path):
		push_warning("MissionParamsIO: file not found: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("MissionParamsIO: cannot open " + path)
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("MissionParamsIO: parse error: " + json.get_error_message())
		return {}
	return json.get_data()

static func save_params(data: Dictionary) -> bool:
	var path := _json_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("MissionParamsIO: cannot write " + path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true
