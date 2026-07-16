class_name GDSQLConfigFileCatalogAdministrationService
extends GDSQLCatalogAdministrationService

var _path_resolver: GDSQLDatabasePathResolver
var _catalog: GDSQLCatalogService
var _cache: GDSQLConfigFileCache


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		catalog: GDSQLCatalogService,
		cache: GDSQLConfigFileCache,
) -> void:
	_path_resolver = path_resolver
	_catalog = catalog
	_cache = cache


func create_database(database_name: StringName) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			&"GDSQL_CATALOG_INVALID_DATABASE_NAME",
			"Database name '%s' must be a valid identifier." % database_name,
		)
	var registry_path := _path_resolver.resolve_catalog_path()
	var directory_error := _ensure_directory(registry_path.get_base_dir())
	if directory_error != OK:
		return _error(
			&"GDSQL_CATALOG_DIRECTORY_UNWRITABLE",
			"Could not create catalog directory '%s'." % registry_path.get_base_dir(),
		)
	var registry := ConfigFile.new()
	var load_error := registry.load(registry_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return _error(
			&"GDSQL_CATALOG_UNREADABLE",
			"Could not read database catalog '%s'." % registry_path,
		)
	if registry.has_section(String(database_name)):
		return _error(
			&"GDSQL_CATALOG_DATABASE_EXISTS",
			"Database '%s' is already registered." % database_name,
		)
	for folder in ["schema", "tables", "mappers", "graphs"]:
		var folder_path := _path_resolver.resolve_database_path(database_name).path_join(folder)
		if _ensure_directory(folder_path) != OK:
			return _error(
				&"GDSQL_CATALOG_DIRECTORY_UNWRITABLE",
				"Could not create database directory '%s'." % folder_path,
			)
	registry.set_value(
		String(database_name),
		"path",
		_path_resolver.resolve_database_path(database_name),
	)
	if registry.save(registry_path) != OK:
		return _error(
			&"GDSQL_CATALOG_SAVE_FAILED",
			"Could not save database catalog '%s'." % registry_path,
		)
	var definition := GDSQLDatabaseDefinition.new()
	definition.name = database_name
	var result := GDSQLCatalogOperationResult.new()
	result.value = definition
	return result


func rename_database(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(current_name) or not _path_resolver.is_valid_name(new_name):
		return _error(&"GDSQL_CATALOG_INVALID_DATABASE_NAME", "Database names must be valid identifiers.")
	var registry_result := _load_registry()
	if not registry_result.is_successful():
		return registry_result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(current_name)):
		return _error(&"GDSQL_CATALOG_UNKNOWN_DATABASE", "Database '%s' is not registered." % current_name)
	if registry.has_section(String(new_name)):
		return _error(&"GDSQL_CATALOG_DATABASE_EXISTS", "Database '%s' is already registered." % new_name)
	var old_path := _path_resolver.resolve_database_path(current_name)
	var new_path := _path_resolver.resolve_database_path(new_name)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(new_path)):
		return _error(&"GDSQL_CATALOG_DATABASE_DIRECTORY_EXISTS", "Database directory '%s' already exists." % new_path)
	var database := _catalog.get_database(current_name)
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(old_path),
		ProjectSettings.globalize_path(new_path),
	) != OK:
		return _error(&"GDSQL_CATALOG_DATABASE_RENAME_FAILED", "Could not rename database directory '%s'." % old_path)
	registry.erase_section(String(current_name))
	registry.set_value(String(new_name), "path", new_path)
	if registry.save(_path_resolver.resolve_catalog_path()) != OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(new_path), ProjectSettings.globalize_path(old_path))
		return _error(&"GDSQL_CATALOG_SAVE_FAILED", "Could not save the renamed database registration.")
	_invalidate_database_tables(database, current_name)
	var definition := _catalog.get_database(new_name)
	var result := GDSQLCatalogOperationResult.new()
	result.value = definition
	return result


func drop_database(database_name: StringName) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(database_name):
		return _error(&"GDSQL_CATALOG_INVALID_DATABASE_NAME", "Invalid database name '%s'." % database_name)
	var registry_result := _load_registry()
	if not registry_result.is_successful():
		return registry_result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(database_name)):
		return _error(&"GDSQL_CATALOG_UNKNOWN_DATABASE", "Database '%s' is not registered." % database_name)
	var database := _catalog.get_database(database_name)
	var registered_path: Variant = registry.get_value(String(database_name), "path", _path_resolver.resolve_database_path(database_name))
	registry.erase_section(String(database_name))
	if registry.save(_path_resolver.resolve_catalog_path()) != OK:
		return _error(&"GDSQL_CATALOG_SAVE_FAILED", "Could not remove database '%s' from the catalog." % database_name)
	var database_path := _path_resolver.resolve_database_path(database_name)
	if _remove_directory_recursive(database_path) != OK:
		registry.set_value(String(database_name), "path", registered_path)
		registry.save(_path_resolver.resolve_catalog_path())
		return _error(&"GDSQL_CATALOG_DATABASE_DROP_FAILED", "Could not remove database directory '%s'." % database_path)
	_invalidate_database_tables(database, database_name)
	var result := GDSQLCatalogOperationResult.new()
	result.value = database
	return result


func create_table(
		database_name: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLCatalogOperationResult:
	var validation := _validate_table(database_name, table)
	if not validation.is_successful():
		return validation
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK \
			or not registry.has_section(String(database_name)):
		return _error(
			&"GDSQL_CATALOG_UNKNOWN_DATABASE",
			"Database '%s' is not registered." % database_name,
		)
	var schema_path := _path_resolver.resolve_schema_path(database_name, table.name)
	var table_path := _path_resolver.resolve_table_path(database_name, table.name)
	if FileAccess.file_exists(schema_path):
		if not FileAccess.file_exists(table_path) and _stored_schema_matches(database_name, table):
			return _complete_missing_table_storage(database_name, table, table_path)
		return _error(
			&"GDSQL_CATALOG_TABLE_EXISTS",
			"Table '%s.%s' already exists." % [database_name, table.name],
		)
	if FileAccess.file_exists(table_path):
		return _error(
			&"GDSQL_CATALOG_TABLE_STORAGE_EXISTS",
			"Table storage '%s' already exists without a schema." % table_path,
		)
	if _ensure_directory(schema_path.get_base_dir()) != OK:
		return _error(
			&"GDSQL_CATALOG_DIRECTORY_UNWRITABLE",
			"Could not create schema directory '%s'." % schema_path.get_base_dir(),
		)
	if _ensure_directory(table_path.get_base_dir()) != OK:
		return _error(
			&"GDSQL_CATALOG_DIRECTORY_UNWRITABLE",
			"Could not create table directory '%s'." % table_path.get_base_dir(),
		)
	var empty_table := ConfigFile.new()
	if empty_table.save(table_path) != OK:
		return _error(
			&"GDSQL_CATALOG_TABLE_STORAGE_CREATE_FAILED",
			"Could not create table storage '%s'." % table_path,
		)
	var schema := ConfigFile.new()
	schema.set_value("table", "name", String(table.name))
	schema.set_value("table", "primary_key", String(table.primary_key))
	for column in table.columns:
		var section := "column:%s" % column.name
		schema.set_value(section, "type", column.data_type)
		schema.set_value(section, "nullable", column.nullable)
		schema.set_value(section, "unique", column.unique)
		schema.set_value(section, "auto_increment", column.auto_increment)
		if column.default_value != null:
			schema.set_value(section, "default", column.default_value)
	if schema.save(schema_path) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(table_path))
		return _error(
			&"GDSQL_CATALOG_SCHEMA_SAVE_FAILED",
			"Could not save table schema '%s'." % schema_path,
		)
	table.database_name = database_name
	var result := GDSQLCatalogOperationResult.new()
	result.value = table
	return result


func rename_table(
		database_name: StringName,
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(new_name):
		return _error(&"GDSQL_CATALOG_INVALID_TABLE_NAME", "Table name '%s' is not a valid identifier." % new_name)
	var table := _catalog.get_table(database_name, current_name)
	if table == null:
		return _error(&"GDSQL_CATALOG_UNKNOWN_TABLE", "Table '%s.%s' does not exist." % [database_name, current_name])
	if _catalog.has_table(database_name, new_name):
		return _error(&"GDSQL_CATALOG_TABLE_EXISTS", "Table '%s.%s' already exists." % [database_name, new_name])
	var old_schema_path := _path_resolver.resolve_schema_path(database_name, current_name)
	var new_schema_path := _path_resolver.resolve_schema_path(database_name, new_name)
	var old_table_path := _path_resolver.resolve_table_path(database_name, current_name)
	var new_table_path := _path_resolver.resolve_table_path(database_name, new_name)
	if FileAccess.file_exists(new_schema_path) or FileAccess.file_exists(new_table_path):
		return _error(&"GDSQL_CATALOG_TABLE_TARGET_EXISTS", "Target files for table '%s' already exist." % new_name)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(old_table_path), ProjectSettings.globalize_path(new_table_path)) != OK:
		return _error(&"GDSQL_CATALOG_TABLE_RENAME_FAILED", "Could not rename table storage '%s'." % old_table_path)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(old_schema_path), ProjectSettings.globalize_path(new_schema_path)) != OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(new_table_path), ProjectSettings.globalize_path(old_table_path))
		return _error(&"GDSQL_CATALOG_TABLE_RENAME_FAILED", "Could not rename table schema '%s'." % old_schema_path)
	var schema := ConfigFile.new()
	if schema.load(new_schema_path) != OK:
		_rollback_table_rename(old_schema_path, new_schema_path, old_table_path, new_table_path)
		return _error(&"GDSQL_CATALOG_SCHEMA_UNREADABLE", "Could not read renamed table schema '%s'." % new_schema_path)
	schema.set_value("table", "name", String(new_name))
	if schema.save(new_schema_path) != OK:
		_rollback_table_rename(old_schema_path, new_schema_path, old_table_path, new_table_path)
		return _error(&"GDSQL_CATALOG_SCHEMA_SAVE_FAILED", "Could not update renamed table schema '%s'." % new_schema_path)
	_cache.invalidate(old_table_path)
	_cache.invalidate(new_table_path)
	table.name = new_name
	var result := GDSQLCatalogOperationResult.new()
	result.value = table
	return result


func drop_table(
		database_name: StringName,
		table_name: StringName,
) -> GDSQLCatalogOperationResult:
	var table := _catalog.get_table(database_name, table_name)
	if table == null:
		return _error(&"GDSQL_CATALOG_UNKNOWN_TABLE", "Table '%s.%s' does not exist." % [database_name, table_name])
	var schema_path := _path_resolver.resolve_schema_path(database_name, table_name)
	var table_path := _path_resolver.resolve_table_path(database_name, table_name)
	var schema := ConfigFile.new()
	var table_data := ConfigFile.new()
	if schema.load(schema_path) != OK or table_data.load(table_path) != OK:
		return _error(&"GDSQL_CATALOG_TABLE_UNREADABLE", "Could not load table '%s.%s' before dropping it." % [database_name, table_name])
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(schema_path)) != OK:
		return _error(&"GDSQL_CATALOG_TABLE_DROP_FAILED", "Could not remove table schema '%s'." % schema_path)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(table_path)) != OK:
		schema.save(schema_path)
		return _error(&"GDSQL_CATALOG_TABLE_DROP_FAILED", "Could not remove table storage '%s'." % table_path)
	_cache.invalidate(table_path)
	var result := GDSQLCatalogOperationResult.new()
	result.value = table
	return result


func alter_table(
		database_name: StringName,
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLCatalogOperationResult:
	if alterations.is_empty():
		return _error(&"GDSQL_CATALOG_ALTERATIONS_REQUIRED", "At least one table alteration is required.")
	var table := _catalog.get_table(database_name, table_name)
	if table == null:
		return _error(&"GDSQL_CATALOG_UNKNOWN_TABLE", "Table '%s.%s' does not exist." % [database_name, table_name])
	var table_path := _path_resolver.resolve_table_path(database_name, table_name)
	var table_data := ConfigFile.new()
	if table_data.load(table_path) != OK:
		return _error(&"GDSQL_CATALOG_TABLE_UNREADABLE", "Could not read table storage '%s'." % table_path)
	var original_data := ConfigFile.new()
	original_data.parse(table_data.encode_to_text())
	for alteration in alterations:
		var alteration_result := _apply_alteration(table, table_data, alteration)
		if not alteration_result.is_successful():
			return alteration_result
	var validation := _validate_table(database_name, table)
	if not validation.is_successful():
		return validation
	var schema_path := _path_resolver.resolve_schema_path(database_name, table_name)
	var original_schema := ConfigFile.new()
	if original_schema.load(schema_path) != OK:
		return _error(&"GDSQL_CATALOG_SCHEMA_UNREADABLE", "Could not read table schema '%s'." % schema_path)
	if table_data.save(table_path) != OK:
		return _error(&"GDSQL_CATALOG_TABLE_SAVE_FAILED", "Could not save altered table storage '%s'." % table_path)
	if _save_schema(schema_path, table) != OK:
		original_data.save(table_path)
		original_schema.save(schema_path)
		return _error(&"GDSQL_CATALOG_SCHEMA_SAVE_FAILED", "Could not save altered table schema '%s'." % schema_path)
	_cache.invalidate(table_path)
	var result := GDSQLCatalogOperationResult.new()
	result.value = table
	return result


func _complete_missing_table_storage(
		database_name: StringName,
		table: GDSQLTableDefinition,
		table_path: String,
) -> GDSQLCatalogOperationResult:
	if _ensure_directory(table_path.get_base_dir()) != OK:
		return _error(
			&"GDSQL_CATALOG_DIRECTORY_UNWRITABLE",
			"Could not create table directory '%s'." % table_path.get_base_dir(),
		)
	var empty_table := ConfigFile.new()
	if empty_table.save(table_path) != OK:
		return _error(
			&"GDSQL_CATALOG_TABLE_STORAGE_CREATE_FAILED",
			"Could not create table storage '%s'." % table_path,
		)
	table.database_name = database_name
	var result := GDSQLCatalogOperationResult.new()
	result.value = table
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_CATALOG_TABLE_STORAGE_COMPLETED",
			"Created missing storage for table '%s.%s'." % [database_name, table.name],
			GDSQLQueryDiagnostic.Severity.INFO,
		),
	)
	return result


func _stored_schema_matches(
		database_name: StringName,
		requested: GDSQLTableDefinition,
) -> bool:
	var stored := _catalog.get_table(database_name, requested.name)
	if stored == null \
			or stored.primary_key != requested.primary_key \
			or stored.columns.size() != requested.columns.size():
		return false
	for requested_column in requested.columns:
		var stored_column := stored.get_column(requested_column.name)
		if stored_column == null \
				or stored_column.data_type != requested_column.data_type \
				or stored_column.nullable != requested_column.nullable \
				or stored_column.unique != requested_column.unique \
				or stored_column.auto_increment != requested_column.auto_increment \
				or stored_column.default_value != requested_column.default_value:
			return false
	return true


func _apply_alteration(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		alteration: GDSQLTableAlteration,
) -> GDSQLCatalogOperationResult:
	if alteration == null:
		return _error(&"GDSQL_CATALOG_INVALID_ALTERATION", "Table alteration cannot be null.")
	match alteration.kind:
		GDSQLTableAlteration.Kind.ADD_COLUMN:
			return _add_column(table, table_data, alteration.column)
		GDSQLTableAlteration.Kind.RENAME_COLUMN:
			return _rename_column(table, table_data, alteration.column_name, alteration.new_column_name)
		GDSQLTableAlteration.Kind.DROP_COLUMN:
			return _drop_column(table, table_data, alteration.column_name)
	return _error(&"GDSQL_CATALOG_INVALID_ALTERATION", "Unsupported table alteration kind.")


func _add_column(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column: GDSQLColumnDefinition,
) -> GDSQLCatalogOperationResult:
	if column == null or not _path_resolver.is_valid_name(column.name) or column.data_type == TYPE_NIL:
		return _error(&"GDSQL_CATALOG_INVALID_COLUMN", "Added column requires a valid name and Variant type.")
	if table.has_column(column.name):
		return _error(&"GDSQL_CATALOG_DUPLICATE_COLUMN", "Column '%s' already exists." % column.name)
	if column.default_value != null and typeof(column.default_value) != column.data_type:
		return _error(
			&"GDSQL_CATALOG_COLUMN_DEFAULT_TYPE_MISMATCH",
			"Default for column '%s' does not match its Variant type." % column.name,
		)
	var row_count := table_data.get_sections().size()
	if row_count > 0 and not column.nullable and column.default_value == null:
		return _error(
			&"GDSQL_CATALOG_COLUMN_DEFAULT_REQUIRED",
			"Non-nullable column '%s' requires a default when rows already exist." % column.name,
		)
	if row_count > 1 and column.unique and column.default_value != null:
		return _error(
			&"GDSQL_CATALOG_COLUMN_UNIQUE_DEFAULT_CONFLICT",
			"Unique column '%s' cannot apply one default to multiple existing rows." % column.name,
		)
	if column.default_value != null:
		for section in table_data.get_sections():
			table_data.set_value(section, String(column.name), column.default_value)
	table.columns.append(column)
	return GDSQLCatalogOperationResult.new()


func _rename_column(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(new_name):
		return _error(&"GDSQL_CATALOG_INVALID_COLUMN_NAME", "Column name '%s' is not a valid identifier." % new_name)
	var column := table.get_column(current_name)
	if column == null:
		return _error(&"GDSQL_CATALOG_UNKNOWN_COLUMN", "Column '%s' does not exist." % current_name)
	if table.has_column(new_name):
		return _error(&"GDSQL_CATALOG_DUPLICATE_COLUMN", "Column '%s' already exists." % new_name)
	for section in table_data.get_sections():
		if table_data.has_section_key(section, String(current_name)):
			var value: Variant = table_data.get_value(section, String(current_name))
			table_data.erase_section_key(section, String(current_name))
			table_data.set_value(section, String(new_name), value)
	column.name = new_name
	if table.primary_key == current_name:
		table.primary_key = new_name
	return GDSQLCatalogOperationResult.new()


func _drop_column(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column_name: StringName,
) -> GDSQLCatalogOperationResult:
	if table.primary_key == column_name:
		return _error(&"GDSQL_CATALOG_PRIMARY_KEY_DROP_FORBIDDEN", "Primary-key column '%s' cannot be dropped." % column_name)
	var column := table.get_column(column_name)
	if column == null:
		return _error(&"GDSQL_CATALOG_UNKNOWN_COLUMN", "Column '%s' does not exist." % column_name)
	for section in table_data.get_sections():
		table_data.erase_section_key(section, String(column_name))
	table.columns.erase(column)
	return GDSQLCatalogOperationResult.new()


func _save_schema(path: String, table: GDSQLTableDefinition) -> Error:
	var schema := ConfigFile.new()
	schema.set_value("table", "name", String(table.name))
	schema.set_value("table", "primary_key", String(table.primary_key))
	for column in table.columns:
		var section := "column:%s" % column.name
		schema.set_value(section, "type", column.data_type)
		schema.set_value(section, "nullable", column.nullable)
		schema.set_value(section, "unique", column.unique)
		schema.set_value(section, "auto_increment", column.auto_increment)
		if column.default_value != null:
			schema.set_value(section, "default", column.default_value)
	return schema.save(path)


func _load_registry() -> GDSQLCatalogOperationResult:
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK:
		return _error(&"GDSQL_CATALOG_UNREADABLE", "Could not read the database catalog.")
	var result := GDSQLCatalogOperationResult.new()
	result.value = registry
	return result


func _rollback_table_rename(
		old_schema_path: String,
		new_schema_path: String,
		old_table_path: String,
		new_table_path: String,
) -> void:
	DirAccess.rename_absolute(ProjectSettings.globalize_path(new_schema_path), ProjectSettings.globalize_path(old_schema_path))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(new_table_path), ProjectSettings.globalize_path(old_table_path))


func _invalidate_database_tables(database: GDSQLDatabaseDefinition, database_name: StringName) -> void:
	if database == null:
		return
	for table in database.tables:
		_cache.invalidate(_path_resolver.resolve_table_path(database_name, table.name))


func _remove_directory_recursive(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name in directory.get_files():
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
		if error != OK:
			return error
	for directory_name in directory.get_directories():
		var error := _remove_directory_recursive(path.path_join(directory_name))
		if error != OK:
			return error
	return DirAccess.remove_absolute(absolute_path)


func _validate_table(
		database_name: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(database_name):
		return _error(&"GDSQL_CATALOG_INVALID_DATABASE_NAME", "Invalid database name '%s'." % database_name)
	if table == null or not _path_resolver.is_valid_name(table.name):
		return _error(&"GDSQL_CATALOG_INVALID_TABLE_NAME", "Table name must be a valid identifier.")
	if table.columns.is_empty():
		return _error(&"GDSQL_CATALOG_COLUMNS_REQUIRED", "Table '%s' requires at least one column." % table.name)
	var column_names: Dictionary = { }
	for column in table.columns:
		if column == null or not _path_resolver.is_valid_name(column.name):
			return _error(&"GDSQL_CATALOG_INVALID_COLUMN_NAME", "Every column requires a valid identifier name.")
		if column_names.has(column.name):
			return _error(&"GDSQL_CATALOG_DUPLICATE_COLUMN", "Column '%s' appears more than once." % column.name)
		if column.data_type == TYPE_NIL:
			return _error(&"GDSQL_CATALOG_COLUMN_TYPE_REQUIRED", "Column '%s' requires a Variant type." % column.name)
		column_names[column.name] = true
	if table.primary_key == &"" or not column_names.has(table.primary_key):
		return _error(&"GDSQL_CATALOG_PRIMARY_KEY_REQUIRED", "Table primary key must reference a declared column.")
	var primary_key := table.get_primary_key()
	primary_key.nullable = false
	primary_key.unique = true
	return GDSQLCatalogOperationResult.new()


func _ensure_directory(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _error(code: StringName, message: String) -> GDSQLCatalogOperationResult:
	var result := GDSQLCatalogOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
