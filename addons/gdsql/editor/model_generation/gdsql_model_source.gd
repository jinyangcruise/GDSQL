class_name GDSQLModelSource
extends RefCounted
## Previewable table-to-model output. Writing the sources remains an editor concern.

var model_class_name: StringName
var generated_class_name: StringName
var generated_path: String
var user_path: String
var generated_source: String
var user_source: String


func _init(
		model_name: StringName = &"",
		generated_name: StringName = &"",
		generated_script_path: String = "",
		user_script_path: String = "",
		generated_script_source: String = "",
		user_script_source: String = "",
) -> void:
	model_class_name = model_name
	generated_class_name = generated_name
	generated_path = generated_script_path
	user_path = user_script_path
	generated_source = generated_script_source
	user_source = user_script_source
