class_name GDSQLDatabaseContext
extends RefCounted

var catalog: GDSQLCatalogService
var catalog_administration: GDSQLCatalogAdministrationService
var storage: GDSQLTableStorage
var validator: GDSQLQueryValidator
var planner: GDSQLQueryPlanner
var executor: GDSQLQueryExecutor
var execution_context: GDSQLExecutionContext


func _init(
		_catalog: GDSQLCatalogService = null,
		_catalog_administration: GDSQLCatalogAdministrationService = null,
		_storage: GDSQLTableStorage = null,
		_validator: GDSQLQueryValidator = null,
		_planner: GDSQLQueryPlanner = null,
		_executor: GDSQLQueryExecutor = null,
		_execution_context: GDSQLExecutionContext = null,
) -> void:
	catalog = _catalog
	catalog_administration = _catalog_administration
	storage = _storage
	validator = _validator
	planner = _planner
	executor = _executor
	execution_context = _execution_context


func create_database(database_name: StringName) -> GDSQLCatalogOperationResult:
	return catalog_administration.create_database(database_name)


func rename_database(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	return catalog_administration.rename_database(current_name, new_name)


func drop_database(database_name: StringName) -> GDSQLCatalogOperationResult:
	return catalog_administration.drop_database(database_name)


func create_table(
		database_name: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLCatalogOperationResult:
	return catalog_administration.create_table(database_name, table)


func rename_table(
		database_name: StringName,
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult:
	return catalog_administration.rename_table(database_name, current_name, new_name)


func drop_table(
		database_name: StringName,
		table_name: StringName,
) -> GDSQLCatalogOperationResult:
	return catalog_administration.drop_table(database_name, table_name)


func alter_table(
		database_name: StringName,
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLCatalogOperationResult:
	return catalog_administration.alter_table(database_name, table_name, alterations)


func execute(query: GDSQLQuerySpec) -> GDSQLQueryResult:
	return _execute(query, execution_context)


func execute_in_session(
		query: GDSQLQuerySpec,
		session: GDSQLStorageSession,
) -> GDSQLQueryResult:
	return _execute(query, execution_context.for_session(session))


func transaction(callback: Callable) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not callback.is_valid():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_TRANSACTION_CALLBACK_REQUIRED",
				"A valid transaction callback is required.",
			),
		)
		return result
	var session := execution_context.transactions.begin()
	var transaction_scope := GDSQLTransaction.new(self, session)
	callback.call(transaction_scope)
	transaction_scope._close()
	result.diagnostics.merge(transaction_scope.diagnostics)
	if transaction_scope._has_failed():
		execution_context.transactions.rollback(session)
		return result
	var commit_result := execution_context.transactions.commit(session)
	result.diagnostics.merge(commit_result.diagnostics)
	if not commit_result.is_successful():
		execution_context.transactions.rollback(session)
		return result
	result.value = true
	return result


func _execute(
		query: GDSQLQuerySpec,
		query_execution_context: GDSQLExecutionContext,
) -> GDSQLQueryResult:
	var public_result := GDSQLQueryResult.new()
	var validation := validator.validate(query)
	public_result.diagnostics.merge(validation.diagnostics)
	if not validation.is_valid():
		return public_result
	var planning := planner.create_plan(validation.bound_query)
	public_result.diagnostics.merge(planning.diagnostics)
	if not planning.is_successful() or planning.plan == null:
		return public_result
	var execution := executor.execute(planning.plan, query_execution_context)
	public_result.diagnostics.merge(execution.diagnostics)
	if execution.rows != null:
		public_result.rows = execution.rows.rows.duplicate()
		public_result.schema = execution.rows.schema
	public_result.statistics = execution.statistics.duplicate()
	public_result.value = public_result.rows
	return public_result


func prepare(query: GDSQLQuerySpec) -> GDSQLQueryPlanningResult:
	var validation := validator.validate(query)
	if not validation.is_valid():
		var result := GDSQLQueryPlanningResult.new()
		result.diagnostics.merge(validation.diagnostics)
		return result
	return planner.create_plan(validation.bound_query)
