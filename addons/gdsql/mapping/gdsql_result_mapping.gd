class_name GDSQLResultMapping
extends RefCounted

var resource_script: Script
var _column_targets: Dictionary = { }


static func for_resource(script: Script) -> GDSQLResultMapping:
	return GDSQLResultMapping.new(script)


func _init(_resource_script: Script = null) -> void:
	resource_script = _resource_script


func map_column(
		source_column: StringName,
		target_name: StringName,
) -> GDSQLResultMapping:
	_column_targets[source_column] = target_name
	return self


func get_target_name(source_column: StringName) -> StringName:
	return _column_targets.get(source_column, source_column)


func get_source_columns() -> Array[StringName]:
	var columns: Array[StringName] = []
	for column: StringName in _column_targets:
		columns.append(column)
	return columns


func has_explicit_columns() -> bool:
	return not _column_targets.is_empty()


func get_column_targets() -> Dictionary:
	return _column_targets.duplicate()
