extends RefCounted
## Test-owned copy of the Godot-AI custom-tool descriptor contract.
##
## Godot-AI is an optional, ignored development addon. Integration tests inject
## this descriptor so the published GDSQL surface can be verified in CI without
## requiring that addon to be installed.

var name: String = ""
var description: String = ""
var params_schema: Dictionary = { }
var script_path: String = ""
var method: StringName = &""
var source_path: String = ""
var source: String = ""
var promoted := false
var timeout_ms := 4500
var deferred := false
var requires_writable := false
var undoable := false


func validate() -> Array[String]:
	var errors: Array[String] = []
	if name.is_empty() or not name.is_valid_ascii_identifier():
		errors.append("name must be a valid identifier")
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		errors.append("script_path must exist")
	if method.is_empty():
		errors.append("method must not be empty")
	if source_path.is_empty() or not source_path.ends_with("plugin.cfg") \
			or not FileAccess.file_exists(source_path):
		errors.append("source_path must reference an existing plugin.cfg")
	if timeout_ms < 500 or timeout_ms > 120_000:
		errors.append("timeout_ms is outside the Godot-AI contract")
	return errors
