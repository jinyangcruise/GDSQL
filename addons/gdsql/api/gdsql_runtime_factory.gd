class_name GDSQLRuntimeFactory
extends RefCounted

const FunctionCatalog = preload("res://addons/gdsql/query/model/gdsql_query_function_catalog.gd")
const FunctionDefinition = preload("res://addons/gdsql/query/model/gdsql_query_function_definition.gd")

static func create_default(settings: Variant = null) -> GDSQLDatabaseContext:
	var data_root := "res://data"
	if settings is String:
		data_root = settings
	elif settings is Dictionary:
		data_root = settings.get("data_root", data_root)
	var path_resolver := GDSQLDatabasePathResolver.new(data_root)
	var cache := GDSQLConfigFileCache.new()
	var codec := GDSQLGodotVariantCodec.new()
	var storage: GDSQLTableStorage = GDSQLConfigFileTableStorage.new(path_resolver, cache, codec)
	var catalog: GDSQLCatalogService = GDSQLConfigFileCatalogService.new(path_resolver)
	var catalog_administration: GDSQLCatalogAdministrationService = \
			GDSQLConfigFileCatalogAdministrationService.new(path_resolver, catalog, cache)
	var transactions := GDSQLTransactionManager.new(storage)
	var function_catalog := FunctionCatalog.new()
	var function_registry := GDSQLQueryFunctionRegistry.new(function_catalog)
	function_catalog.register_function(
		FunctionDefinition.new(&"count", 0, 1, TYPE_INT, true),
	)
	function_catalog.register_function(
		FunctionDefinition.new(&"sum", 1, 1, TYPE_FLOAT, true),
	)
	function_catalog.register_function(
		FunctionDefinition.new(&"avg", 1, 1, TYPE_FLOAT, true),
	)
	function_catalog.register_function(
		FunctionDefinition.new(&"min", 1, 1, TYPE_NIL, true),
	)
	function_catalog.register_function(
		FunctionDefinition.new(&"max", 1, 1, TYPE_NIL, true),
	)
	var expression_evaluator := GDSQLExpressionEvaluator.new(function_registry)
	var cancellation := GDSQLQueryCancellationToken.new()
	var execution_context := GDSQLExecutionContext.new(
		catalog,
		storage,
		transactions,
		expression_evaluator,
		function_registry,
		cancellation,
	)
	return GDSQLDatabaseContext.new(
		catalog,
		catalog_administration,
		storage,
		GDSQLDefaultQueryValidator.new(catalog, function_catalog),
		GDSQLDefaultQueryPlanner.new(),
		GDSQLDefaultQueryExecutor.new(),
		execution_context,
	)
