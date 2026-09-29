class_name GDSQLForeignKeyConstraintValidator
extends RefCounted
## Validates same-database foreign keys against the final state of a storage session.

var _catalog: GDSQLCatalogService
var _storage: GDSQLTableStorage


func _init(
		catalog: GDSQLCatalogService,
		storage: GDSQLTableStorage,
) -> void:
	assert(catalog != null)
	assert(storage != null)
	_catalog = catalog
	_storage = storage


func validate(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	var databases: Dictionary[StringName, bool] = { }
	for operation in session.operations:
		var table := operation.get("table") as GDSQLTableDefinition
		if table != null:
			databases[table.database_name] = true
	for database_name in databases:
		var database := _catalog.get_database(database_name)
		if database == null:
			return _error(
				&"GDSQL_STORAGE_FOREIGN_KEY_DATABASE_MISSING",
				"Cannot validate foreign keys for missing database '%s'." % database_name,
			)
		var validation := _validate_database(database, session)
		if not validation.is_successful():
			return validation
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _validate_database(
		database: GDSQLDatabaseDefinition,
		session: GDSQLStorageSession,
) -> GDSQLStorageCommitResult:
	for table in database.tables:
		if table.foreign_keys.is_empty():
			continue
		var local_snapshot := _storage.read_table(table, session)
		if local_snapshot == null:
			return _unreadable_table(table)
		for foreign_key in table.foreign_keys:
			var referenced_table := database.get_table(foreign_key.referenced_table)
			if referenced_table == null:
				return _error(
					&"GDSQL_STORAGE_FOREIGN_KEY_TARGET_MISSING",
					"Foreign key '%s' references missing table '%s.%s'." % [
						foreign_key.name,
						database.name,
						foreign_key.referenced_table,
					],
				)
			var target_snapshot := _storage.read_table(referenced_table, session)
			if target_snapshot == null:
				return _unreadable_table(referenced_table)
			var target_values: Dictionary = { }
			for target_row in target_snapshot.rows:
				var target_value: Variant = target_row.get_value(
					foreign_key.referenced_column,
				)
				if target_value != null:
					target_values[target_value] = true
			for local_row in local_snapshot.rows:
				var local_value: Variant = local_row.get_value(foreign_key.column)
				if local_value != null and not target_values.has(local_value):
					return _error(
						&"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
						"Foreign key '%s' value '%s' has no matching '%s.%s' row." % [
							foreign_key.name,
							local_value,
							foreign_key.referenced_table,
							foreign_key.referenced_column,
						],
					)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _unreadable_table(table: GDSQLTableDefinition) -> GDSQLStorageCommitResult:
	return _error(
		&"GDSQL_STORAGE_FOREIGN_KEY_TABLE_UNREADABLE",
		"Could not read table '%s.%s' while validating foreign keys." % [
			table.database_name,
			table.name,
		],
	)


func _error(code: StringName, message: String) -> GDSQLStorageCommitResult:
	var result := GDSQLStorageCommitResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
