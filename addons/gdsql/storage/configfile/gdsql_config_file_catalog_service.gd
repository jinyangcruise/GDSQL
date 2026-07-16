class_name GDSQLConfigFileCatalogService
extends GDSQLCatalogService

var _path_resolver: GDSQLDatabasePathResolver
var _codec: GDSQLGodotVariantCodec


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		codec: GDSQLGodotVariantCodec,
) -> void:
	_path_resolver = path_resolver
	_codec = codec


func get_database(database_name: StringName) -> GDSQLDatabaseDefinition:
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK:
		return null
	if not registry.has_section(String(database_name)):
		return null
	var database := GDSQLDatabaseDefinition.new()
	database.name = database_name
	var schema_directory := _path_resolver.resolve_catalog_path(database_name)
	var directory := DirAccess.open(schema_directory)
	if directory == null:
		return database
	for file_name in directory.get_files():
		if file_name.get_extension() != "cfg":
			continue
		var table := _load_table(database_name, StringName(file_name.get_basename()))
		if table != null:
			database.tables.append(table)
	return database


func get_table(database_name: StringName, table_name: StringName) -> GDSQLTableDefinition:
	if not has_table(database_name, table_name):
		return null
	return _load_table(database_name, table_name)


func has_table(database_name: StringName, table_name: StringName) -> bool:
	if get_database_registration(database_name).is_empty():
		return false
	return FileAccess.file_exists(_path_resolver.resolve_schema_path(database_name, table_name))


func create_snapshot() -> GDSQLCatalogSnapshot:
	var snapshot := GDSQLCatalogSnapshot.new()
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK:
		return snapshot
	for section in registry.get_sections():
		if section == "gdsql":
			continue
		var database := get_database(StringName(section))
		if database != null:
			snapshot.databases.append(database)
	return snapshot


func get_database_registration(database_name: StringName) -> Dictionary:
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK:
		return { }
	if not registry.has_section(String(database_name)):
		return { }
	return {
		"name": String(database_name),
		"path": registry.get_value(
			String(database_name),
			"path",
			_path_resolver.resolve_database_path(database_name),
		),
	}


func _load_table(database_name: StringName, table_name: StringName) -> GDSQLTableDefinition:
	var schema := ConfigFile.new()
	if schema.load(_path_resolver.resolve_schema_path(database_name, table_name)) != OK:
		return null
	var table := GDSQLTableDefinition.new()
	table.database_name = database_name
	table.name = StringName(schema.get_value("table", "name", String(table_name)))
	table.primary_key = StringName(schema.get_value("table", "primary_key", ""))
	for section in schema.get_sections():
		if not section.begins_with("column:"):
			continue
		var column_name := StringName(section.trim_prefix("column:"))
		var column := GDSQLColumnDefinition.new(
			column_name,
			int(schema.get_value(section, "type", TYPE_NIL)) as Variant.Type,
			bool(schema.get_value(section, "nullable", true)),
		)
		column.unique = bool(schema.get_value(section, "unique", false))
		column.auto_increment = bool(schema.get_value(section, "auto_increment", false))
		column.generation = int(
			schema.get_value(
				section,
				"generation",
				GDSQLColumnDefinition.Generation.NONE,
			),
		)
		if schema.has_section_key(section, "default_kind") \
				and schema.get_value(section, "default_kind") == "static":
			column.set_default(
				_codec.decode(schema.get_value(section, "default")) \
					if schema.has_section_key(section, "default") \
					else null,
			)
		table.columns.append(column)
	return table
