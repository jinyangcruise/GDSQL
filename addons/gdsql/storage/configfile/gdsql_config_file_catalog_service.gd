class_name GDSQLConfigFileCatalogService
extends GDSQLCatalogService

var _path_resolver: GDSQLDatabasePathResolver
var _codec: GDSQLGodotVariantCodec
var _catalog_transaction: GDSQLConfigFileCatalogTransaction
var _table_lifecycle: GDSQLConfigFileTableLifecycleTransaction


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		codec: GDSQLGodotVariantCodec,
		catalog_transaction: GDSQLConfigFileCatalogTransaction = null,
		table_lifecycle: GDSQLConfigFileTableLifecycleTransaction = null,
) -> void:
	_path_resolver = path_resolver
	_codec = codec
	_catalog_transaction = catalog_transaction \
	if catalog_transaction != null \
	else GDSQLConfigFileCatalogTransaction.new(path_resolver)
	_table_lifecycle = table_lifecycle \
	if table_lifecycle != null \
	else GDSQLConfigFileTableLifecycleTransaction.new(path_resolver)


func get_database(database_name: StringName) -> GDSQLDatabaseDefinition:
	var registry := ConfigFile.new()
	if registry.load(_path_resolver.resolve_catalog_path()) != OK:
		return null
	if not registry.has_section(String(database_name)):
		return null
	if not _table_lifecycle.recover_database(database_name).is_successful():
		return null
	if not _catalog_transaction.recover_database(database_name).is_successful():
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
	if not _table_lifecycle.recover_database(database_name).is_successful() \
			or not _catalog_transaction.recover_table(
				database_name,
				table_name,
			).is_successful():
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
		if section.begins_with("column:"):
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
			column.resource_type = _load_resource_type(schema, section, column.data_type)
			column.resource_ownership = GDSQLResourceOwnership.from_id(
				StringName(schema.get_value(section, "resource_ownership", "owned")),
			)
			if schema.has_section_key(section, "default_kind") \
					and schema.get_value(section, "default_kind") == "static":
				column.set_default(
					_codec.decode(schema.get_value(section, "default"), column) \
					if schema.has_section_key(section, "default") \
					else null,
				)
			table.columns.append(column)
		elif section.begins_with("index:"):
			var index_columns: Array[StringName] = []
			for column_name in schema.get_value(section, "columns", PackedStringArray()):
				index_columns.append(StringName(column_name))
			table.indexes.append(
				GDSQLIndexDefinition.new(
					StringName(section.trim_prefix("index:")),
					index_columns,
					bool(schema.get_value(section, "unique", false)),
				),
			)
		elif section.begins_with("foreign_key:"):
			table.foreign_keys.append(
				GDSQLForeignKeyDefinition.new(
					StringName(section.trim_prefix("foreign_key:")),
					StringName(schema.get_value(section, "column", "")),
					StringName(schema.get_value(section, "referenced_table", "")),
					StringName(schema.get_value(section, "referenced_column", "")),
					int(
						schema.get_value(
							section,
							"on_delete",
							GDSQLForeignKeyDefinition.Action.RESTRICT,
						),
					) as GDSQLForeignKeyDefinition.Action,
					int(
						schema.get_value(
							section,
							"on_update",
							GDSQLForeignKeyDefinition.Action.RESTRICT,
						),
					) as GDSQLForeignKeyDefinition.Action,
				),
			)
	return table


func _load_resource_type(
		schema: ConfigFile,
		section: String,
		data_type: Variant.Type,
) -> GDSQLResourceTypeConstraint:
	if data_type != TYPE_OBJECT:
		return null
	return GDSQLResourceTypeConstraint.from_serialized(
		StringName(schema.get_value(section, "resource_class", "")),
		String(schema.get_value(section, "resource_script", "")),
	)
