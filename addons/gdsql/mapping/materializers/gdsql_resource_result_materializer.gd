class_name GDSQLResourceResultMaterializer
extends GDSQLResultMaterializer

func materialize(rows: GDSQLRowSet, mapping: GDSQLResultMapping = null) -> GDSQLQueryResult:
	var result := _create_result(rows)
	if not result.is_successful():
		return result
	if mapping == null or mapping.resource_script == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MATERIALIZATION_RESOURCE_SCRIPT_REQUIRED",
				"Resource materialization requires a target Resource script.",
			),
		)
		return result
	var resources: Array[Resource] = []
	for row in rows.rows:
		var candidate: Variant = mapping.resource_script.new()
		if not candidate is Resource:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_MATERIALIZATION_RESOURCE_REQUIRED",
					"The target script must extend Resource.",
				),
			)
			return result
		var resource := candidate as Resource
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
			if not _has_property(resource, property_name):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_MATERIALIZATION_UNKNOWN_PROPERTY",
						"Resource property '%s' does not exist." % property_name,
					),
				)
				return result
			resource.set(property_name, row.get_value(source_column))
		resources.append(resource)
	result.value = resources
	return result


func _has_property(resource: Resource, property_name: StringName) -> bool:
	for property in resource.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
