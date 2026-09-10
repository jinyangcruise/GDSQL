class_name GDSQLModelCompatibilityInspector
extends RefCounted
## Inspects model metadata without changing the table or either model script.

func inspect(
		model_script: Script,
		table: GDSQLTableDefinition,
		expected_role: StringName,
) -> GDSQLModelCompatibilityReport:
	var report := GDSQLModelCompatibilityReport.new()
	if table == null:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_TABLE_REQUIRED",
			"A table definition is required for model compatibility inspection.",
		)
		return report
	var registered := GDSQLModelRegistry.new().register(model_script)
	report.diagnostics.merge(registered.diagnostics)
	if not registered.is_successful():
		return report
	report.definition = registered.get_value() as GDSQLModelDefinition
	_compare_identity(report, table, expected_role)
	_compare_properties(report, model_script, table)
	_inspect_relationships(report)
	return report


func _compare_identity(
		report: GDSQLModelCompatibilityReport,
		table: GDSQLTableDefinition,
		expected_role: StringName,
) -> void:
	var definition := report.definition
	if definition.database_role != expected_role:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_ROLE_MISMATCH",
			"Model role '%s' does not match the table's configured role '%s'." \
					% [definition.database_role, expected_role],
		)
	if definition.table_name != table.name:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_TABLE_MISMATCH",
			"Model table '%s' does not match '%s'." % [definition.table_name, table.name],
		)
	if definition.primary_key != table.primary_key:
		_add_error(
			report,
			&"GDSQL_MODEL_COMPATIBILITY_PRIMARY_KEY_MISMATCH",
			"Model primary key '%s' does not match '%s'." \
					% [definition.primary_key, table.primary_key],
		)


func _compare_properties(
		report: GDSQLModelCompatibilityReport,
		model_script: Script,
		table: GDSQLTableDefinition,
) -> void:
	var model := model_script.new() as GDSQLModel
	var properties: Dictionary[StringName, Dictionary] = { }
	for property in model.get_property_list():
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
		var actual_type := int(properties[column.name].get("type", TYPE_NIL)) as Variant.Type
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


func _inspect_relationships(report: GDSQLModelCompatibilityReport) -> void:
	for relationship in report.definition.get_relationships():
		var related := relationship.related_model_script.new() as GDSQLModel
		report.relationship_summaries.append(
			"%s · %s → %s.%s (%s → %s)" % [
				relationship.name,
				_kind_name(relationship.kind),
				related.database_role(),
				related.table_name(),
				relationship.local_key,
				relationship.related_key,
			],
		)


func _expected_property_type(column: GDSQLColumnDefinition) -> Variant.Type:
	if column.nullable and column.data_type != TYPE_OBJECT:
		return TYPE_NIL
	return column.data_type


func _kind_name(kind: GDSQLRelationshipDefinition.Kind) -> String:
	match kind:
		GDSQLRelationshipDefinition.Kind.BELONGS_TO:
			return "belongs to"
		GDSQLRelationshipDefinition.Kind.HAS_ONE:
			return "has one"
		GDSQLRelationshipDefinition.Kind.HAS_MANY:
			return "has many"
	return "relationship"


func _add_error(
		report: GDSQLModelCompatibilityReport,
		code: StringName,
		message: String,
) -> void:
	report.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
