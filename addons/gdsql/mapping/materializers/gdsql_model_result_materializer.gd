class_name GDSQLModelResultMaterializer
extends GDSQLResultMaterializer

var _model_context: GDSQLModelContext


func _init(model_context: GDSQLModelContext = null) -> void:
	_model_context = model_context


func materialize(rows: GDSQLRowSet, mapping: GDSQLResultMapping = null) -> GDSQLQueryResult:
	var result := _create_result(rows)
	if not result.is_successful():
		return result
	if mapping == null or mapping.resource_script == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MATERIALIZATION_MODEL_SCRIPT_REQUIRED",
				"Model materialization requires a target model script.",
			),
		)
		return result
	var models: Array[GDSQLModel] = []
	for row in rows.rows:
		var candidate: Variant = mapping.resource_script.new()
		if not candidate is GDSQLModel:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_MATERIALIZATION_MODEL_REQUIRED",
					"The target script must extend GDSQLModel.",
				),
			)
			return result
		var model := candidate as GDSQLModel
		var materialized_values: Dictionary[StringName, Variant] = { }
		for source_column in _source_columns(row, mapping):
			if not row.has_column(source_column):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_MATERIALIZATION_UNKNOWN_COLUMN",
						"Result column '%s' does not exist." % source_column,
					),
				)
				return result
			var property_name := mapping.get_target_name(source_column)
			if not _has_property(model, property_name):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_MATERIALIZATION_UNKNOWN_PROPERTY",
						"Model property '%s' does not exist." % property_name,
					),
				)
				return result
			var value: Variant = row.get_value(source_column)
			model.set(property_name, value)
			materialized_values[property_name] = value
		model._attach_model_context(_model_context, true, materialized_values)
		models.append(model)
	result.value = Array(
		models,
		TYPE_OBJECT,
		&"RefCounted",
		mapping.resource_script,
	)
	return result


func _has_property(model: GDSQLModel, property_name: StringName) -> bool:
	for property in model.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
