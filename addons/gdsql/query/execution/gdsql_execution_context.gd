class_name GDSQLExecutionContext
extends RefCounted

var catalog: GDSQLCatalogService
var storage: GDSQLTableStorage
var transactions: GDSQLTransactionManager
var expression_evaluator: GDSQLExpressionEvaluator
var function_registry: GDSQLQueryFunctionRegistry
var cancellation: GDSQLQueryCancellationToken
var session: GDSQLStorageSession


func _init(
		_catalog: GDSQLCatalogService = null,
		_storage: GDSQLTableStorage = null,
		_transactions: GDSQLTransactionManager = null,
		_expression_evaluator: GDSQLExpressionEvaluator = null,
		_function_registry: GDSQLQueryFunctionRegistry = null,
		_cancellation: GDSQLQueryCancellationToken = null,
		_session: GDSQLStorageSession = null,
) -> void:
	catalog = _catalog
	storage = _storage
	transactions = _transactions
	expression_evaluator = _expression_evaluator
	function_registry = _function_registry
	cancellation = _cancellation
	session = _session


func for_session(storage_session: GDSQLStorageSession) -> GDSQLExecutionContext:
	return GDSQLExecutionContext.new(
		catalog,
		storage,
		transactions,
		expression_evaluator,
		function_registry,
		cancellation,
		storage_session,
	)
