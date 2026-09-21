class_name GDSQLModelCompatibilityInspector
extends RefCounted
## Statically inspects model inheritance and properties without executing user code.


func inspect(
		model_script: Script,
		table: GDSQLTableDefinition,
		expected_role: StringName,
		expected_generated_path: String = "",
) -> GDSQLModelCompatibilityReport:
	var report := GDSQLModelCompatibilityReport.new()
	if table == null:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_TABLE_REQUIRED",
			"A table definition is required for model compatibility inspection.",
		)
		return report
	if model_script == null:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_SCRIPT_UNAVAILABLE",
			"Godot could not load the user model script. See Output for its parser error.",
		)
		return report
	_compare_inheritance(report, model_script, expected_role)
	_compare_generated_base(report, model_script, expected_generated_path)
	_compare_properties(report, model_script, table)
	return report


func _compare_inheritance(
		report: GDSQLModelCompatibilityReport,
		model_script: Script,
		expected_role: StringName,
) -> void:
	var expected_base := _base_script(expected_role)
	if _inherits_script(model_script, expected_base):
		return
	_add_error(
		report,
		&"GDSQL_MODEL_COMPATIBILITY_ROLE_MISMATCH",
		"The model does not inherit %s, required by role '%s'." % [
			expected_base.get_global_name(),
			expected_role,
		],
	)


func _compare_generated_base(
		report: GDSQLModelCompatibilityReport,
		model_script: Script,
		expected_path: String,
) -> void:
	if expected_path.is_empty():
		return
	var base_script := model_script.get_base_script()
	if base_script != null and base_script.resource_path == expected_path:
		return
	_add_error(
		report,
		&"GDSQL_MODEL_COMPATIBILITY_GENERATED_BASE_MISMATCH",
		"The user model must directly extend '%s'." % expected_path,
	)


func _compare_properties(
		report: GDSQLModelCompatibilityReport,
		model_script: Script,
		table: GDSQLTableDefinition,
) -> void:
	var properties: Dictionary[StringName, Dictionary] = { }
	for property in model_script.get_script_property_list():
		properties[StringName(property.get("name", ""))] = property
	for column in table.columns:
		if not properties.has(column.name):
			_add_error(
				report,
				&"GDSQL_MODEL_COMPATIBILITY_PROPERTY_MISSING",
				"Column '%s' has no matching model property." % column.name,
			)
			continue
		var expected_type := _expected_property_type(column)
		var actual_type := int(properties[column.name].get("type", TYPE_NIL)) \
				as Variant.Type
		if actual_type != expected_type:
			_add_error(
				report,
				&"GDSQL_MODEL_COMPATIBILITY_TYPE_MISMATCH",
				"Property '%s' uses %s; the table requires %s." % [
					column.name,
					type_string(actual_type),
					type_string(expected_type),
				],
			)


func _inherits_script(model_script: Script, expected_base: Script) -> bool:
	var current := model_script
	while current != null:
		if current == expected_base:
			return true
		current = current.get_base_script()
	return false


func _base_script(database_role: StringName) -> Script:
	match database_role:
		GDSQLDatabaseRegistry.CONTENT_ROLE:
			return GDSQLContentModel
		GDSQLDatabaseRegistry.SAVE_ROLE:
			return GDSQLSaveModel
		GDSQLDatabaseRegistry.SETTINGS_ROLE:
			return GDSQLSettingsModel
		_:
			return GDSQLModel


func _expected_property_type(column: GDSQLColumnDefinition) -> Variant.Type:
	if column.nullable and column.data_type != TYPE_OBJECT:
		return TYPE_NIL
	return column.data_type


func _add_error(
		report: GDSQLModelCompatibilityReport,
		code: StringName,
		message: String,
) -> void:
	report.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
