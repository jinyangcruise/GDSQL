class_name GDSQLDictionaryResultMaterializer
extends GDSQLResultMaterializer

func materialize(rows: GDSQLRowSet, mapping: GDSQLResultMapping = null) -> GDSQLQueryResult:
	var result := _create_result(rows)
	if not result.is_successful():
		return result
	var dictionaries: Array[Dictionary] = []
	for row in rows.rows:
		var dictionary: Dictionary = { }
		for source_column in _source_columns(row, mapping):
			if not row.has_column(source_column):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_MATERIALIZATION_UNKNOWN_COLUMN",
						"Result column '%s' does not exist." % source_column,
					),
				)
				return result
			var target_name := source_column \
			if mapping == null \
			else mapping.get_target_name(source_column)
			if dictionary.has(target_name):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_MATERIALIZATION_DUPLICATE_TARGET",
						"More than one result column maps to '%s'." % target_name,
					),
				)
				return result
			dictionary[target_name] = row.get_value(source_column)
		dictionaries.append(dictionary)
	result.value = dictionaries
	return result
