class_name GDSQLConfigFileCatalogAdministrationService
extends GDSQLCatalogAdministrationService

const TABLE_METADATA_SECTION := "__gdsql_metadata__"
const INDEX_SECTION_PREFIX := "__gdsql_index__:"

var _path_resolver: GDSQLDatabasePathResolver
var _catalog: GDSQLCatalogService
var _cache: GDSQLConfigFileCache
var _codec: GDSQLGodotVariantCodec


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		catalog: GDSQLCatalogService,
		cache: GDSQLConfigFileCache,
		codec: GDSQLGodotVariantCodec,
) -> void:
	_path_resolver = path_resolver
	_catalog = catalog
	_cache = cache
	_codec = codec


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
	for folder in ["schema", "tables"]:
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


func unregister_database(
		database_name: StringName,
) -> GDSQLCatalogOperationResult:
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			&"GDSQL_CATALOG_INVALID_DATABASE_NAME",
			"Invalid database name '%s'." % database_name,
		)
	var registry_result := _load_registry()
	if not registry_result.is_successful():
		return registry_result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(database_name)):
		return _error(
			&"GDSQL_CATALOG_UNKNOWN_DATABASE",
			"Database '%s' is not registered." % database_name,
		)
	var database := _catalog.get_database(database_name)
	registry.erase_section(String(database_name))
	if registry.save(_path_resolver.resolve_catalog_path()) != OK:
		return _error(
			&"GDSQL_CATALOG_SAVE_FAILED",
			"Could not unregister database '%s' from the catalog." \
					% database_name,
		)
	_invalidate_database_tables(database, database_name)
	var result := GDSQLCatalogOperationResult.new()
	result.value = database
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
	_initialize_table_metadata(empty_table)
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
		schema.set_value(section, "generation", column.generation)
		_write_resource_type(schema, section, column)
		if column.has_default():
			schema.set_value(section, "default_kind", "static")
			if column.get_default_value() != null:
				schema.set_value(
					section,
					"default",
					_codec.encode(column.get_default_value()),
				)
	_write_index_schema(schema, table)
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
	var preview := preview_alter_table(database_name, table_name, alterations)
	if not preview.is_successful():
		var failed := GDSQLCatalogOperationResult.new()
		failed.diagnostics.merge(preview.diagnostics)
		return failed
	return apply_change_plan(preview.get_value() as GDSQLCatalogChangePlan)


func preview_alter_table(
		database_name: StringName,
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLOperationResult:
	if alterations.is_empty():
		return _operation_error(
			&"GDSQL_CATALOG_ALTERATIONS_REQUIRED",
			"At least one table alteration is required.",
		)
	var table := _catalog.get_table(database_name, table_name)
	if table == null:
		return _operation_error(
			&"GDSQL_CATALOG_UNKNOWN_TABLE",
			"Table '%s.%s' does not exist." % [database_name, table_name],
		)
	var table_path := _path_resolver.resolve_table_path(database_name, table_name)
	var table_data := ConfigFile.new()
	if table_data.load(table_path) != OK:
		return _operation_error(
			&"GDSQL_CATALOG_TABLE_UNREADABLE",
			"Could not read table storage '%s'." % table_path,
		)
	var source_fingerprint := _catalog_fingerprint(table)
	for alteration in alterations:
		var alteration_result := _apply_alteration(table, table_data, alteration)
		if not alteration_result.is_successful():
			var failed := GDSQLOperationResult.new()
			failed.diagnostics.merge(alteration_result.diagnostics)
			return failed
	var validation := _validate_table(database_name, table)
	if not validation.is_successful():
		var failed := GDSQLOperationResult.new()
		failed.diagnostics.merge(validation.diagnostics)
		return failed
	var result := GDSQLOperationResult.new()
	result.value = GDSQLCatalogChangePlan.new(
		database_name,
		table_name,
		alterations,
		source_fingerprint,
		_get_row_sections(table_data).size(),
	)
	return result


func apply_change_plan(
		plan: GDSQLCatalogChangePlan,
) -> GDSQLCatalogOperationResult:
	if plan == null:
		return _error(
			&"GDSQL_CATALOG_CHANGE_PLAN_REQUIRED",
			"A catalog change plan is required.",
		)
	var current_table := _catalog.get_table(plan.database_name, plan.table_name)
	if current_table == null:
		return _error(
			&"GDSQL_CATALOG_UNKNOWN_TABLE",
			"Table '%s.%s' does not exist." % [plan.database_name, plan.table_name],
		)
	if _catalog_fingerprint(current_table) != plan.source_catalog_fingerprint:
		return _error(
			&"GDSQL_CATALOG_CHANGE_PLAN_STALE",
			"Table '%s.%s' changed after this plan was previewed." \
					% [plan.database_name, plan.table_name],
		)
	return _apply_alterations(
		plan.database_name,
		plan.table_name,
		plan.alterations,
	)


func _apply_alterations(
		database_name: StringName,
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLCatalogOperationResult:
	var table := _catalog.get_table(database_name, table_name)
	var table_path := _path_resolver.resolve_table_path(database_name, table_name)
	var table_data := ConfigFile.new()
	if table_data.load(table_path) != OK:
		return _error(
			&"GDSQL_CATALOG_TABLE_UNREADABLE",
			"Could not read table storage '%s'." % table_path,
		)
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
	_rebuild_indexes(table_data, table)
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
	_initialize_table_metadata(empty_table)
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
			or stored.columns.size() != requested.columns.size() \
			or stored.indexes.size() != requested.indexes.size():
		return false
	for requested_column in requested.columns:
		var stored_column := stored.get_column(requested_column.name)
		if stored_column == null \
				or stored_column.data_type != requested_column.data_type \
				or not _resource_types_match(stored_column, requested_column) \
				or stored_column.nullable != requested_column.nullable \
				or stored_column.unique != requested_column.unique \
				or stored_column.auto_increment != requested_column.auto_increment \
				or stored_column.generation != requested_column.generation \
				or stored_column.has_default() != requested_column.has_default() \
				or stored_column.get_default_value() != requested_column.get_default_value():
			return false
	for requested_index in requested.indexes:
		var stored_index := stored.get_index(requested_index.name)
		if stored_index == null \
				or stored_index.columns != requested_index.columns \
				or stored_index.unique != requested_index.unique:
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
		GDSQLTableAlteration.Kind.ADD_INDEX:
			return _add_index(table, table_data, alteration.index)
		GDSQLTableAlteration.Kind.DROP_INDEX:
			return _drop_index(table, alteration.index_name)
		GDSQLTableAlteration.Kind.SET_COLUMN_DEFAULT:
			return _set_column_default(table, alteration.column_name, alteration.value)
		GDSQLTableAlteration.Kind.CLEAR_COLUMN_DEFAULT:
			return _clear_column_default(table, alteration.column_name)
		GDSQLTableAlteration.Kind.SET_COLUMN_NULLABLE:
			return _set_column_nullable(
				table,
				table_data,
				alteration.column_name,
				alteration.enabled,
			)
		GDSQLTableAlteration.Kind.SET_COLUMN_UNIQUE:
			return _set_column_unique(
				table,
				table_data,
				alteration.column_name,
				alteration.enabled,
			)
		GDSQLTableAlteration.Kind.SET_COLUMN_AUTO_INCREMENT:
			return _set_column_auto_increment(
				table,
				table_data,
				alteration.column_name,
				alteration.enabled,
			)
		GDSQLTableAlteration.Kind.SET_COLUMN_GENERATION:
			return _set_column_generation(
				table,
				alteration.column_name,
				alteration.generation,
			)
	return _error(&"GDSQL_CATALOG_INVALID_ALTERATION", "Unsupported table alteration kind.")


func _add_column(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column: GDSQLColumnDefinition,
) -> GDSQLCatalogOperationResult:
	if column == null or not _path_resolver.is_valid_name(column.name) or column.data_type == TYPE_NIL:
		return _error(&"GDSQL_CATALOG_INVALID_COLUMN", "Added column requires a valid name and Variant type.")
	if not column.has_valid_type_constraint():
		return _error(
			&"GDSQL_CATALOG_RESOURCE_TYPE_REQUIRED",
			"Object column '%s' requires a valid concrete Resource subtype." % column.name,
		)
	if table.has_column(column.name):
		return _error(&"GDSQL_CATALOG_DUPLICATE_COLUMN", "Column '%s' already exists." % column.name)
	if column.has_default() and not column.accepts_value(column.get_default_value()):
		return _error(
			&"GDSQL_CATALOG_COLUMN_DEFAULT_TYPE_MISMATCH",
			"Default for column '%s' does not match its Variant type." % column.name,
		)
	if column.generation != GDSQLColumnDefinition.Generation.NONE:
		if column.data_type != TYPE_INT:
			return _error(
				&"GDSQL_CATALOG_GENERATED_COLUMN_TYPE",
				"Generated timestamp column '%s' must use TYPE_INT." % column.name,
			)
		if column.has_default():
			return _error(
				&"GDSQL_CATALOG_GENERATED_COLUMN_DEFAULT",
				"Generated column '%s' cannot also declare a static default." % column.name,
			)
	var row_count := _get_row_sections(table_data).size()
	if row_count > 0 and not column.nullable and not column.has_default() \
			and column.generation == GDSQLColumnDefinition.Generation.NONE:
		return _error(
			&"GDSQL_CATALOG_COLUMN_DEFAULT_REQUIRED",
			"Non-nullable column '%s' requires a default when rows already exist." % column.name,
		)
	if row_count > 1 and column.unique and column.has_default() \
			and column.get_default_value() != null:
		return _error(
			&"GDSQL_CATALOG_COLUMN_UNIQUE_DEFAULT_CONFLICT",
			"Unique column '%s' cannot apply one default to multiple existing rows." % column.name,
		)
	if column.has_default():
		for section in _get_row_sections(table_data):
			table_data.set_value(
				section,
				String(column.name),
				_codec.encode(column.get_default_value()),
			)
	elif column.generation == GDSQLColumnDefinition.Generation.CREATED_AT \
			or column.generation == GDSQLColumnDefinition.Generation.UPDATED_AT:
		var alteration_timestamp := int(Time.get_unix_time_from_system() * 1000.0)
		for section in _get_row_sections(table_data):
			table_data.set_value(
				section,
				String(column.name),
				alteration_timestamp,
			)
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
	for section in _get_row_sections(table_data):
		if table_data.has_section_key(section, String(current_name)):
			var value: Variant = table_data.get_value(section, String(current_name))
			table_data.erase_section_key(section, String(current_name))
			table_data.set_value(section, String(new_name), value)
	column.name = new_name
	if table.primary_key == current_name:
		table.primary_key = new_name
	for index in table.indexes:
		for column_index in index.columns.size():
			if index.columns[column_index] == current_name:
				index.columns[column_index] = new_name
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
	for index in table.indexes:
		if index.columns.has(column_name):
			return _error(
				&"GDSQL_CATALOG_INDEXED_COLUMN_DROP_FORBIDDEN",
				"Column '%s' cannot be dropped while index '%s' references it." \
						% [column_name, index.name],
			)
	for section in _get_row_sections(table_data):
		table_data.erase_section_key(section, String(column_name))
	table.columns.erase(column)
	return GDSQLCatalogOperationResult.new()


func _add_index(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		index: GDSQLIndexDefinition,
) -> GDSQLCatalogOperationResult:
	if index == null:
		return _error(&"GDSQL_CATALOG_INVALID_INDEX", "Added index cannot be null.")
	if table.get_index(index.name) != null:
		return _error(
			&"GDSQL_CATALOG_DUPLICATE_INDEX",
			"Index '%s' already exists." % index.name,
		)
	if index.unique:
		var uniqueness := _validate_unique_index_data(table_data, index)
		if not uniqueness.is_successful():
			return uniqueness
	table.indexes.append(index)
	return GDSQLCatalogOperationResult.new()


func _drop_index(
		table: GDSQLTableDefinition,
		index_name: StringName,
) -> GDSQLCatalogOperationResult:
	var index := table.get_index(index_name)
	if index == null:
		return _error(
			&"GDSQL_CATALOG_UNKNOWN_INDEX",
			"Index '%s' does not exist." % index_name,
		)
	table.indexes.erase(index)
	return GDSQLCatalogOperationResult.new()


func _set_column_default(
		table: GDSQLTableDefinition,
		column_name: StringName,
		value: Variant,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	if column.generation != GDSQLColumnDefinition.Generation.NONE:
		return _error(
			&"GDSQL_CATALOG_GENERATED_COLUMN_DEFAULT",
			"Generated column '%s' cannot also declare a static default." % column_name,
		)
	if not column.accepts_value(value):
		return _error(
			&"GDSQL_CATALOG_COLUMN_DEFAULT_TYPE_MISMATCH",
			"Default for column '%s' does not match its Variant type." % column_name,
		)
	column.set_default(value)
	return GDSQLCatalogOperationResult.new()


func _clear_column_default(
		table: GDSQLTableDefinition,
		column_name: StringName,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	column.clear_default()
	return GDSQLCatalogOperationResult.new()


func _set_column_nullable(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column_name: StringName,
		nullable: bool,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	if column_name == table.primary_key and nullable:
		return _error(
			&"GDSQL_CATALOG_PRIMARY_KEY_NULLABLE_FORBIDDEN",
			"Primary-key column '%s' cannot be nullable." % column_name,
		)
	if not nullable:
		for section in _get_row_sections(table_data):
			if not table_data.has_section_key(section, String(column_name)) \
					or _read_value(table_data, section, column_name) == null:
				return _error(
					&"GDSQL_CATALOG_COLUMN_CONTAINS_NULL",
					"Column '%s' contains null or missing values." % column_name,
				)
	column.nullable = nullable
	return GDSQLCatalogOperationResult.new()


func _set_column_unique(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column_name: StringName,
		unique: bool,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	if column_name == table.primary_key and not unique:
		return _error(
			&"GDSQL_CATALOG_PRIMARY_KEY_UNIQUE_REQUIRED",
			"Primary-key column '%s' must remain unique." % column_name,
		)
	if unique:
		var uniqueness := _validate_unique_column_data(table_data, column_name)
		if not uniqueness.is_successful():
			return uniqueness
	column.unique = unique
	return GDSQLCatalogOperationResult.new()


func _set_column_auto_increment(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
		column_name: StringName,
		auto_increment: bool,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	column.auto_increment = auto_increment
	if auto_increment:
		_recalculate_auto_increment(table, table_data)
	return GDSQLCatalogOperationResult.new()


func _set_column_generation(
		table: GDSQLTableDefinition,
		column_name: StringName,
		generation: GDSQLColumnDefinition.Generation,
) -> GDSQLCatalogOperationResult:
	var column := table.get_column(column_name)
	if column == null:
		return _unknown_column(column_name)
	if generation < GDSQLColumnDefinition.Generation.NONE \
			or generation > GDSQLColumnDefinition.Generation.UPDATED_AT:
		return _error(
			&"GDSQL_CATALOG_GENERATION_INVALID",
			"Column '%s' received an unknown generation policy." % column_name,
		)
	if generation != GDSQLColumnDefinition.Generation.NONE and column.has_default():
		return _error(
			&"GDSQL_CATALOG_GENERATED_COLUMN_DEFAULT",
			"Generated column '%s' cannot also declare a static default." % column_name,
		)
	column.generation = generation
	return GDSQLCatalogOperationResult.new()


func _validate_unique_column_data(
		table_data: ConfigFile,
		column_name: StringName,
) -> GDSQLCatalogOperationResult:
	var seen: Array[Variant] = []
	for section in _get_row_sections(table_data):
		var value: Variant = _read_value(table_data, section, column_name)
		if value == null:
			continue
		if seen.has(value):
			return _error(
				&"GDSQL_CATALOG_DUPLICATE_UNIQUE_VALUE",
				"Column '%s' contains duplicate value '%s'." % [column_name, value],
			)
		seen.append(value)
	return GDSQLCatalogOperationResult.new()


func _validate_unique_index_data(
		table_data: ConfigFile,
		index: GDSQLIndexDefinition,
) -> GDSQLCatalogOperationResult:
	var seen: Array[Array] = []
	for section in _get_row_sections(table_data):
		var values: Array = []
		var contains_null := false
		for column_name in index.columns:
			var value: Variant = _read_value(table_data, section, column_name)
			values.append(value)
			contains_null = contains_null or value == null
		if contains_null:
			continue
		if seen.has(values):
			return _error(
				&"GDSQL_CATALOG_DUPLICATE_INDEX_VALUE",
				"Unique index '%s' has duplicate value '%s'." % [index.name, values],
			)
		seen.append(values)
	return GDSQLCatalogOperationResult.new()


func _read_value(
		table_data: ConfigFile,
		section: String,
		column_name: StringName,
) -> Variant:
	if not table_data.has_section_key(section, String(column_name)):
		return null
	return _codec.decode(table_data.get_value(section, String(column_name)))


func _recalculate_auto_increment(
		table: GDSQLTableDefinition,
		table_data: ConfigFile,
) -> void:
	var next_value := 1
	for section in _get_row_sections(table_data):
		var value: Variant = _read_value(table_data, section, table.primary_key)
		if value is int:
			next_value = maxi(next_value, value + 1)
	table_data.set_value(TABLE_METADATA_SECTION, "next_auto_increment", next_value)


func _unknown_column(column_name: StringName) -> GDSQLCatalogOperationResult:
	return _error(
		&"GDSQL_CATALOG_UNKNOWN_COLUMN",
		"Column '%s' does not exist." % column_name,
	)


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
		schema.set_value(section, "generation", column.generation)
		_write_resource_type(schema, section, column)
		if column.has_default():
			schema.set_value(section, "default_kind", "static")
			if column.get_default_value() != null:
				schema.set_value(
					section,
					"default",
					_codec.encode(column.get_default_value()),
				)
	_write_index_schema(schema, table)
	return schema.save(path)


func _write_index_schema(
		schema: ConfigFile,
		table: GDSQLTableDefinition,
) -> void:
	for index in table.indexes:
		var section := "index:%s" % index.name
		var columns := PackedStringArray()
		for column_name in index.columns:
			columns.append(String(column_name))
		schema.set_value(section, "columns", columns)
		schema.set_value(section, "unique", index.unique)


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
	var auto_increment_columns := 0
	for column in table.columns:
		if column == null or not _path_resolver.is_valid_name(column.name):
			return _error(&"GDSQL_CATALOG_INVALID_COLUMN_NAME", "Every column requires a valid identifier name.")
		if column_names.has(column.name):
			return _error(&"GDSQL_CATALOG_DUPLICATE_COLUMN", "Column '%s' appears more than once." % column.name)
		if column.data_type == TYPE_NIL:
			return _error(&"GDSQL_CATALOG_COLUMN_TYPE_REQUIRED", "Column '%s' requires a Variant type." % column.name)
		if not column.has_valid_type_constraint():
			return _error(
				&"GDSQL_CATALOG_RESOURCE_TYPE_REQUIRED",
				"Object column '%s' requires a valid concrete Resource subtype." % column.name,
			)
		if column.has_default() and not column.accepts_value(column.get_default_value()):
			return _error(
				&"GDSQL_CATALOG_COLUMN_DEFAULT_TYPE_MISMATCH",
				"Default for column '%s' does not match its Variant type." % column.name,
			)
		if column.auto_increment:
			auto_increment_columns += 1
			if column.data_type != TYPE_INT:
				return _error(
					&"GDSQL_CATALOG_AUTO_INCREMENT_TYPE",
					"Auto-increment column '%s' must use TYPE_INT." % column.name,
				)
		if column.generation != GDSQLColumnDefinition.Generation.NONE:
			if column.data_type != TYPE_INT:
				return _error(
					&"GDSQL_CATALOG_GENERATED_COLUMN_TYPE",
					"Generated timestamp column '%s' must use TYPE_INT." % column.name,
				)
			if column.has_default():
				return _error(
					&"GDSQL_CATALOG_GENERATED_COLUMN_DEFAULT",
					"Generated column '%s' cannot also declare a static default." % column.name,
				)
		column_names[column.name] = true
	if table.primary_key == &"" or not column_names.has(table.primary_key):
		return _error(&"GDSQL_CATALOG_PRIMARY_KEY_REQUIRED", "Table primary key must reference a declared column.")
	var primary_key := table.get_primary_key()
	primary_key.nullable = false
	primary_key.unique = true
	if auto_increment_columns > 1:
		return _error(
			&"GDSQL_CATALOG_AUTO_INCREMENT_COUNT",
			"Only one auto-increment column is supported per table.",
		)
	if auto_increment_columns == 1 and not primary_key.auto_increment:
		return _error(
			&"GDSQL_CATALOG_AUTO_INCREMENT_PRIMARY_KEY",
			"The initial auto-increment implementation requires the primary key.",
		)
	var index_names: Dictionary = { }
	for index in table.indexes:
		if index == null or not _path_resolver.is_valid_name(index.name):
			return _error(
				&"GDSQL_CATALOG_INVALID_INDEX_NAME",
				"Every index requires a valid identifier name.",
			)
		if index_names.has(index.name):
			return _error(
				&"GDSQL_CATALOG_DUPLICATE_INDEX",
				"Index '%s' appears more than once." % index.name,
			)
		if index.columns.is_empty():
			return _error(
				&"GDSQL_CATALOG_INDEX_COLUMNS_REQUIRED",
				"Index '%s' requires at least one column." % index.name,
			)
		var indexed_columns: Dictionary = { }
		for column_name in index.columns:
			if not column_names.has(column_name):
				return _error(
					&"GDSQL_CATALOG_INDEX_UNKNOWN_COLUMN",
					"Index '%s' references unknown column '%s'." \
							% [index.name, column_name],
				)
			if indexed_columns.has(column_name):
				return _error(
					&"GDSQL_CATALOG_INDEX_DUPLICATE_COLUMN",
					"Index '%s' references column '%s' more than once." \
							% [index.name, column_name],
				)
			var indexed_column := table.get_column(column_name)
			if indexed_column.data_type == TYPE_OBJECT:
				return _error(
					&"GDSQL_CATALOG_INDEX_UNSUPPORTED_TYPE",
					"Index '%s' cannot reference Resource column '%s'." \
							% [index.name, column_name],
				)
			indexed_columns[column_name] = true
		index_names[index.name] = true
	return GDSQLCatalogOperationResult.new()


func _initialize_table_metadata(table_data: ConfigFile) -> void:
	table_data.set_value(TABLE_METADATA_SECTION, "row_count", 0)
	table_data.set_value(TABLE_METADATA_SECTION, "next_auto_increment", 1)


func _get_row_sections(table_data: ConfigFile) -> PackedStringArray:
	var sections := PackedStringArray()
	for section in table_data.get_sections():
		if section != TABLE_METADATA_SECTION \
				and not section.begins_with(INDEX_SECTION_PREFIX):
			sections.append(section)
	return sections


func _rebuild_indexes(
		table_data: ConfigFile,
		table: GDSQLTableDefinition,
) -> void:
	for section in table_data.get_sections():
		if section.begins_with(INDEX_SECTION_PREFIX):
			table_data.erase_section(section)
	for index in table.indexes:
		for row_section in _get_row_sections(table_data):
			var values: Array[Variant] = []
			for column_name in index.columns:
				var value: Variant = _read_value(
					table_data,
					row_section,
					column_name,
				)
				var column := table.get_column(column_name)
				if value != null and column != null:
					match column.data_type:
						TYPE_INT:
							value = int(value)
						TYPE_FLOAT:
							value = float(value)
						TYPE_STRING:
							value = String(value)
						TYPE_STRING_NAME:
							value = StringName(value)
				values.append(value)
			var section := "%s%s:%s" % [
				INDEX_SECTION_PREFIX,
				index.name,
				var_to_bytes(values).hex_encode(),
			]
			if not table_data.has_section(section):
				var encoded_values: Array = []
				for value in values:
					encoded_values.append(_codec.encode(value))
				table_data.set_value(section, "values", encoded_values)
				table_data.set_value(
					section,
					"rows",
					PackedStringArray([row_section]),
				)
				continue
			var rows: PackedStringArray = table_data.get_value(
				section,
				"rows",
				PackedStringArray(),
			)
			rows.append(row_section)
			table_data.set_value(section, "rows", rows)


func _catalog_fingerprint(table: GDSQLTableDefinition) -> int:
	var columns: Array = []
	for column in table.columns:
		columns.append(
			[
				column.name,
				column.data_type,
				column.nullable,
				column.unique,
				column.auto_increment,
				column.generation,
				column.has_default(),
				column.get_default_value(),
				column.resource_type.resource_class if column.resource_type != null else &"",
				column.resource_type.script_path if column.resource_type != null else "",
			],
		)
	var indexes: Array = []
	for index in table.indexes:
		indexes.append([index.name, index.columns, index.unique])
	return hash(
		var_to_str(
			[
				table.database_name,
				table.name,
				table.primary_key,
				columns,
				indexes,
			],
		),
	)


func _write_resource_type(
		schema: ConfigFile,
		section: String,
		column: GDSQLColumnDefinition,
) -> void:
	if column.data_type != TYPE_OBJECT or column.resource_type == null:
		return
	schema.set_value(section, "resource_class", String(column.resource_type.resource_class))
	if not column.resource_type.script_path.is_empty():
		schema.set_value(section, "resource_script", column.resource_type.script_path)


func _resource_types_match(
		left: GDSQLColumnDefinition,
		right: GDSQLColumnDefinition,
) -> bool:
	if left.resource_type == null or right.resource_type == null:
		return left.resource_type == right.resource_type
	return left.resource_type.is_equivalent_to(right.resource_type)


func _ensure_directory(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _operation_error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _error(code: StringName, message: String) -> GDSQLCatalogOperationResult:
	var result := GDSQLCatalogOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
