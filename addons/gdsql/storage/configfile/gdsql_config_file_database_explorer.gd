class_name GDSQLConfigFileDatabaseExplorer
extends GDSQLDatabaseExplorer
## Reads ConfigFile catalogs, schemas, and reserved table metadata only.

const TABLE_METADATA_SECTION := "__gdsql_metadata__"


func inspect_root(
		data_root: String,
		registration_prefix: StringName = &"",
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var resolver := GDSQLDatabasePathResolver.new(data_root)
	var catalog_path := resolver.resolve_catalog_path()
	var catalog := ConfigFile.new()
	var load_error := catalog.load(catalog_path)
	if load_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_DISCOVERY_CATALOG_UNREADABLE",
				"Could not inspect database catalog '%s'." % catalog_path,
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
		var inspections: Array[GDSQLDatabaseInspection] = []
		result.value = inspections
		return result
	var database_names: Array[StringName] = []
	for section in catalog.get_sections():
		if section != "gdsql":
			database_names.append(StringName(section))
	var inspections: Array[GDSQLDatabaseInspection] = []
	for database_name in database_names:
		var registration_name := _registration_name(
			registration_prefix,
			database_name,
			database_names.size(),
		)
		var registration := GDSQLDatabaseRegistration.new(
			registration_name,
			database_name,
			data_root,
			GDSQLStorageBackendIds.CONFIG_FILE,
		)
		var inspection := GDSQLDatabaseInspection.new(registration, true)
		inspection.tables = _inspect_tables(resolver, database_name, result)
		inspections.append(inspection)
	result.value = inspections
	return result


func _inspect_tables(
		resolver: GDSQLDatabasePathResolver,
		database_name: StringName,
		result: GDSQLOperationResult,
) -> Array[GDSQLTableInspection]:
	var inspections: Array[GDSQLTableInspection] = []
	var schema_directory := resolver.resolve_catalog_path(database_name)
	var directory := DirAccess.open(schema_directory)
	if directory == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_DISCOVERY_SCHEMA_DIRECTORY_MISSING",
				"Schema directory for database '%s' is unavailable." % database_name,
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
		return inspections
	for file_name in directory.get_files():
		if file_name.get_extension() != "cfg":
			continue
		var table_name := StringName(file_name.get_basename())
		inspections.append(_inspect_table(resolver, database_name, table_name))
	return inspections


func _inspect_table(
		resolver: GDSQLDatabasePathResolver,
		database_name: StringName,
		table_name: StringName,
) -> GDSQLTableInspection:
	var schema_path := resolver.resolve_schema_path(database_name, table_name)
	var storage_path := resolver.resolve_table_path(database_name, table_name)
	var schema := ConfigFile.new()
	var schema_exists := schema.load(schema_path) == OK
	var column_count := 0
	var index_count := 0
	var columns: Array[GDSQLColumnDefinition] = []
	if schema_exists:
		for section in schema.get_sections():
			if section.begins_with("column:"):
				columns.append(_inspect_column(schema, section))
				column_count += 1
			index_count += int(section.begins_with("index:"))
	var storage := ConfigFile.new()
	var storage_exists := storage.load(storage_path) == OK
	var row_count := 0
	if storage_exists:
		row_count = int(
			storage.get_value(TABLE_METADATA_SECTION, "row_count", 0),
		)
	return GDSQLTableInspection.new(
		table_name,
		schema_exists,
		storage_exists,
		row_count,
		column_count,
		index_count,
		columns,
	)


func _inspect_column(
		schema: ConfigFile,
		section: String,
) -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(
		StringName(section.trim_prefix("column:")),
		int(schema.get_value(section, "type", TYPE_NIL)) as Variant.Type,
		bool(schema.get_value(section, "nullable", true)),
		bool(schema.get_value(section, "unique", false)),
		bool(schema.get_value(section, "auto_increment", false)),
	)
	column.generation = int(
		schema.get_value(
			section,
			"generation",
			GDSQLColumnDefinition.Generation.NONE,
		),
	)
	return column


func _registration_name(
		prefix: StringName,
		database_name: StringName,
		database_count: int,
) -> StringName:
	if prefix == &"":
		return database_name
	if database_count == 1:
		return prefix
	return StringName("%s_%s" % [prefix, database_name])
