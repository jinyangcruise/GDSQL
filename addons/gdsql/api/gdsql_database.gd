class_name GDSQLDatabase
extends RefCounted

var context: GDSQLDatabaseContext
var database_name: StringName


static func open(
		database_name: StringName,
		data_root: String = "res://data",
) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	var database_context := GDSQLRuntimeFactory.create_default(data_root)
	if database_context.catalog.get_database(database_name) == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_NOT_FOUND",
				"Database '%s' is not registered." % database_name,
			),
		)
		return result
	result.value = GDSQLDatabase.new(database_name, database_context)
	return result


static func create(
		database_name: StringName,
		data_root: String = "res://data",
) -> GDSQLDatabaseResult:
	var database_context := GDSQLRuntimeFactory.create_default(data_root)
	var catalog_result := database_context.create_database(database_name)
	var result := GDSQLDatabaseResult.new()
	result.diagnostics.merge(catalog_result.diagnostics)
	if catalog_result.is_successful():
		result.value = GDSQLDatabase.new(database_name, database_context)
	return result


func _init(
		database_name: StringName = &"",
		context: GDSQLDatabaseContext = null,
) -> void:
	self.database_name = database_name
	self.context = context


func query() -> GDSQLQuery:
	return GDSQLQuery.new(database_name)


func table(table_name: StringName) -> GDSQLQuery:
	return query()


func execute(query_spec: GDSQLQuerySpec) -> GDSQLQueryResult:
	return context.execute(query_spec)


func create_table(table_definition: GDSQLTableDefinition) -> GDSQLCatalogOperationResult:
	return context.create_table(database_name, table_definition)


func rename(new_name: StringName) -> GDSQLDatabaseResult:
	var catalog_result := context.rename_database(database_name, new_name)
	var result := GDSQLDatabaseResult.new()
	result.diagnostics.merge(catalog_result.diagnostics)
	if catalog_result.is_successful():
		database_name = new_name
		result.value = self
	return result


func drop() -> GDSQLCatalogOperationResult:
	var result := context.drop_database(database_name)
	if result.is_successful():
		database_name = &""
	return result


func rename_table(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	return context.rename_table(database_name, current_name, new_name)


func drop_table(table_name: StringName) -> GDSQLCatalogOperationResult:
	return context.drop_table(database_name, table_name)


func alter_table(
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLCatalogOperationResult:
	return context.alter_table(database_name, table_name, alterations)


func insert(table_name: StringName, values: Dictionary) -> GDSQLQueryResult:
	var query_spec := query().insert().into_table(table_name).values(values).build()
	return execute(query_spec)


func execute_sql(source: String) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.diagnostics.add(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_SQL_NOT_IMPLEMENTED",
			"SQL execution is not implemented in the current runtime.",
		),
	)
	return result
