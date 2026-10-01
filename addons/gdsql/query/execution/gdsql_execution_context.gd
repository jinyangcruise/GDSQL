class_name GDSQLExecutionContext
extends RefCounted

var catalog: GDSQLCatalogService
var storage: GDSQLTableStorage
var transactions: GDSQLTransactionManager
var expression_evaluator: GDSQLExpressionEvaluator
var function_registry: GDSQLQueryFunctionRegistry
var cancellation: GDSQLQueryCancellationToken
var session: GDSQLStorageSession
var options: GDSQLQueryExecutionOptions


func _init(
		_catalog: GDSQLCatalogService = null,
		_storage: GDSQLTableStorage = null,
		_transactions: GDSQLTransactionManager = null,
		_expression_evaluator: GDSQLExpressionEvaluator = null,
		_function_registry: GDSQLQueryFunctionRegistry = null,
		_cancellation: GDSQLQueryCancellationToken = null,
		_session: GDSQLStorageSession = null,
		_options: GDSQLQueryExecutionOptions = null,
) -> void:
	catalog = _catalog
	storage = _storage
	transactions = _transactions
	expression_evaluator = _expression_evaluator
	function_registry = _function_registry
	cancellation = _cancellation
	session = _session
	options = _options if _options != null else GDSQLQueryExecutionOptions.eager()


func for_session(storage_session: GDSQLStorageSession) -> GDSQLExecutionContext:
	return GDSQLExecutionContext.new(
		catalog,
		storage,
		transactions,
		expression_evaluator,
		function_registry,
		cancellation,
		storage_session,
		options,
	)


func with_options(value: GDSQLQueryExecutionOptions) -> GDSQLExecutionContext:
	return GDSQLExecutionContext.new(
		catalog,
		storage,
		transactions,
		expression_evaluator,
		function_registry,
		cancellation,
		session,
		value,
	)
