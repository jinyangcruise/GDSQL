class_name GDSQLRowRecord
extends RefCounted

var values: Dictionary = { }
var source_values: Dictionary = { }
var aggregate_values: Dictionary = { }


func _init(values: Dictionary = { }) -> void:
	self.values = values.duplicate(true)


func get_value(column: StringName) -> Variant:
	return values.get(column)


func get_source_value(
		table_id: GDSQLTableId,
		column: StringName,
		source_qualifier: StringName = &"",
) -> Variant:
	var source: Dictionary = self.source_values.get(
		_source_key(table_id, source_qualifier),
		{ },
	)
	if source.has(column):
		return source[column]
	return get_value(column)


func set_source_values(
		table_id: GDSQLTableId,
		p_values: Dictionary,
		source_qualifier: StringName = &"",
) -> void:
	self.source_values[_source_key(table_id, source_qualifier)] = p_values.duplicate(true)


func merge_source_values(other: GDSQLRowRecord) -> void:
	for key in other.source_values:
		source_values[key] = (other.source_values[key] as Dictionary).duplicate(true)


func set_value(column: StringName, value: Variant) -> void:
	values[column] = value


func get_aggregate_value(expression: GDSQLFunctionExpression) -> Variant:
	return aggregate_values.get(expression.get_instance_id())


func set_aggregate_value(
		expression: GDSQLFunctionExpression,
		value: Variant,
) -> void:
	aggregate_values[expression.get_instance_id()] = value


func has_column(column: StringName) -> bool:
	return values.has(column)


func duplicate_record() -> GDSQLRowRecord:
	var duplicate := GDSQLRowRecord.new(values)
	duplicate.source_values = source_values.duplicate(true)
	duplicate.aggregate_values = aggregate_values.duplicate(true)
	return duplicate


func _source_key(table_id: GDSQLTableId, source_qualifier: StringName) -> String:
	if table_id == null:
		return ""
	var qualifier := source_qualifier
	if qualifier == &"":
		qualifier = table_id.table_name
	return "%s.%s@%s" % [table_id.database_name, table_id.table_name, qualifier]
