class_name GDSQLEditorFreshSaveProvisioner
extends RefCounted
## Creates a fresh save database at a separately trusted schema head.
##
## Provisioning copies catalog definitions only. It never copies rows from the
## template database and establishes a baseline only after the target schema
## independently matches the project-owned migration state.


func provision(
		template: GDSQLDatabaseDefinition,
		target: GDSQLDatabase,
		history: Array[GDSQLMigrationDefinition],
		schema_state: GDSQLMigrationSchemaState,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var target_definition := _target_definition(target)
	if template == null or target_definition == null:
		return _error(
			result,
			&"GDSQL_FRESH_DATABASE_REQUIRED",
			"Fresh database provisioning requires readable template and target catalogs.",
		)
	if template.name != target.database_name or not target_definition.tables.is_empty():
		return _error(
			result,
			&"GDSQL_FRESH_DATABASE_TARGET_INVALID",
			"Fresh database provisioning requires an empty target with the template's logical database name.",
		)
	if schema_state == null or not schema_state.is_valid() \
			or schema_state.database_name != template.name \
			or not schema_state.matches_history_prefix(history):
		return _error(
			result,
			&"GDSQL_FRESH_DATABASE_SCHEMA_STATE_INVALID",
			"Fresh database provisioning requires trusted schema state for the template migration stream.",
		)
	if GDSQLSchemaFingerprint.compute(template) != schema_state.schema_fingerprint:
		return _error(
			result,
			&"GDSQL_FRESH_DATABASE_TEMPLATE_OUTDATED",
			"The template database is not at its trusted migration schema head.",
		)

	var created_tables: Array[StringName] = []
	var foreign_key_tables: Array[StringName] = []
	for table in template.tables:
		var created := target.create_table(_copy_table_without_foreign_keys(table))
		result.diagnostics.merge(created.diagnostics)
		if not created.is_successful():
			_rollback(target, created_tables, foreign_key_tables, result)
			return result
		created_tables.append(table.name)
	for table in template.tables:
		if table.foreign_keys.is_empty():
			continue
		var alterations: Array[GDSQLTableAlteration] = []
		for foreign_key in table.foreign_keys:
			alterations.append(
				GDSQLTableAlteration.add_foreign_key(_copy_foreign_key(foreign_key)),
			)
		var altered := target.alter_table(table.name, alterations)
		result.diagnostics.merge(altered.diagnostics)
		if not altered.is_successful():
			_rollback(target, created_tables, foreign_key_tables, result)
			return result
		foreign_key_tables.append(table.name)

	if GDSQLSchemaFingerprint.compute(_target_definition(target)) \
			!= schema_state.schema_fingerprint:
		_error(
			result,
			&"GDSQL_FRESH_DATABASE_SCHEMA_MISMATCH",
			"The provisioned database does not match the trusted schema state.",
		)
		_rollback(target, created_tables, foreign_key_tables, result)
		return result
	var adopted := target.adopt_migration_baseline(history, schema_state)
	result.diagnostics.merge(adopted.diagnostics)
	if not adopted.is_successful():
		_rollback(target, created_tables, foreign_key_tables, result)
		return result
	result.value = adopted.get_value()
	return result


func _target_definition(target: GDSQLDatabase) -> GDSQLDatabaseDefinition:
	if target == null or target.context == null or target.context.catalog == null:
		return null
	return target.context.catalog.get_database(target.database_name)


func _copy_table_without_foreign_keys(
		source: GDSQLTableDefinition,
) -> GDSQLTableDefinition:
	var copy := GDSQLTableDefinition.new(source.name, source.primary_key)
	for column in source.columns:
		copy.add_column(_copy_column(column))
	for index in source.indexes:
		copy.add_index(
			GDSQLIndexDefinition.new(index.name, index.columns, index.unique),
		)
	return copy


func _copy_column(source: GDSQLColumnDefinition) -> GDSQLColumnDefinition:
	var resource_type: GDSQLResourceTypeConstraint
	if source.resource_type != null:
		resource_type = GDSQLResourceTypeConstraint.from_serialized(
			source.resource_type.resource_class,
			source.resource_type.script_path,
		)
	var copy := GDSQLColumnDefinition.new(
		source.name,
		source.data_type,
		source.nullable,
		source.unique,
		source.auto_increment,
		null,
		resource_type,
	)
	copy.generation = source.generation
	copy.resource_ownership = source.resource_ownership
	if source.has_default():
		copy.set_default(source.get_default_value())
	return copy


func _copy_foreign_key(
		source: GDSQLForeignKeyDefinition,
) -> GDSQLForeignKeyDefinition:
	return GDSQLForeignKeyDefinition.new(
		source.name,
		source.column,
		source.referenced_table,
		source.referenced_column,
		source.on_delete,
		source.on_update,
	)


func _rollback(
		target: GDSQLDatabase,
		created_tables: Array[StringName],
		foreign_key_tables: Array[StringName],
		result: GDSQLOperationResult,
) -> void:
	foreign_key_tables.reverse()
	for table_name in foreign_key_tables:
		var table := target.context.catalog.get_table(target.database_name, table_name)
		if table == null or table.foreign_keys.is_empty():
			continue
		var alterations: Array[GDSQLTableAlteration] = []
		for foreign_key in table.foreign_keys:
			alterations.append(
				GDSQLTableAlteration.drop_foreign_key(foreign_key.name),
			)
		result.diagnostics.merge(target.alter_table(table_name, alterations).diagnostics)
	created_tables.reverse()
	for table_name in created_tables:
		result.diagnostics.merge(target.drop_table(table_name).diagnostics)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
