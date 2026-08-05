class_name GDSQLWorkbenchSession
extends RefCounted
## UI-independent state and operations for inspecting and editing one
## registered database through the canonical public runtime.

var registration: GDSQLDatabaseRegistration
var database: GDSQLDatabase
var catalog_snapshot: GDSQLCatalogSnapshot
var selected_table: GDSQLTableDefinition
var current_rows: GDSQLQueryResult
var pending_change_plan: GDSQLCatalogChangePlan


func open_registration(
		target: GDSQLDatabaseRegistration,
) -> GDSQLDatabaseResult:
	var result := GDSQLRuntimeFactory.open_registration(target)
	if not result.is_successful():
		return result
	registration = target
	database = result.get_database()
	selected_table = null
	current_rows = null
	pending_change_plan = null
	refresh_catalog()
	return result


func refresh_catalog() -> GDSQLOperationResult:
	if database == null:
		return _operation_error(
			&"GDSQL_WORKBENCH_DATABASE_REQUIRED",
			"Open a database registration before refreshing its catalog.",
		)
	catalog_snapshot = database.context.catalog.create_snapshot()
	var result := GDSQLOperationResult.new()
	result.value = catalog_snapshot
	return result


func select_table(table_name: StringName) -> GDSQLOperationResult:
	if database == null:
		return _operation_error(
			&"GDSQL_WORKBENCH_DATABASE_REQUIRED",
			"Open a database registration before selecting a table.",
		)
	var table := database.context.catalog.get_table(
		database.database_name,
		table_name,
	)
	if table == null:
		return _operation_error(
			&"GDSQL_WORKBENCH_UNKNOWN_TABLE",
			"Table '%s.%s' does not exist." \
					% [database.database_name, table_name],
		)
	selected_table = table
	current_rows = null
	pending_change_plan = null
	var result := GDSQLOperationResult.new()
	result.value = table
	return result


func load_rows(limit: int = 100, offset: int = 0) -> GDSQLQueryResult:
	if selected_table == null:
		return _query_error(
			&"GDSQL_WORKBENCH_TABLE_REQUIRED",
			"Select a table before loading rows.",
		)
	var builder := database.query().select().from_table(selected_table.name)
	if limit >= 0:
		builder.limit(limit)
	if offset > 0:
		builder.offset(offset)
	current_rows = database.execute(builder.build())
	return current_rows


func preview_table_change(
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLOperationResult:
	if selected_table == null:
		return _operation_error(
			&"GDSQL_WORKBENCH_TABLE_REQUIRED",
			"Select a table before previewing schema changes.",
		)
	var result := database.preview_alter_table(selected_table.name, alterations)
	if result.is_successful():
		pending_change_plan = result.get_value() as GDSQLCatalogChangePlan
	return result


func apply_pending_change() -> GDSQLCatalogOperationResult:
	if pending_change_plan == null:
		var result := GDSQLCatalogOperationResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_WORKBENCH_CHANGE_PLAN_REQUIRED",
				"Preview a table change before applying it.",
			),
		)
		return result
	var table_name := pending_change_plan.table_name
	var result := database.apply_change_plan(pending_change_plan)
	if result.is_successful():
		pending_change_plan = null
		refresh_catalog()
		select_table(table_name)
	return result


func _operation_error(
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _query_error(code: StringName, message: String) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
