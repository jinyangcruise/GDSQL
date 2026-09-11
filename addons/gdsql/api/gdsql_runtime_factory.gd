class_name GDSQLRuntimeFactory
extends RefCounted

const FunctionCatalog = preload("res://addons/gdsql/query/model/gdsql_query_function_catalog.gd")


## Builds the supported runtime entry point from editor-authored durable
## registration metadata. ConfigFile registrations are durable on commit;
## in-memory registrations receive explicit checkpoint targets.
static func bootstrap(
		registry_path: String = GDSQLConfigFileDatabaseRegistryStore.DEFAULT_PATH,
		checkpoint_policies: Dictionary = { },
		default_checkpoint_policy: GDSQLCheckpointPolicy = null,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(registry_path),
	)
	var loaded := registry.load_snapshot()
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var persistence := GDSQLPersistenceCoordinator.new()
	var snapshot := loaded.get_value() as GDSQLDatabaseRegistrySnapshot
	var setup := GDSQLDirectSetupInspector.inspect_runtime(snapshot)
	result.diagnostics.merge(setup.diagnostics)
	for registration in snapshot.registrations:
		var opened := open_registration(registration)
		result.diagnostics.merge(opened.diagnostics)
		if not opened.is_successful():
			continue
		var registered := registry.register(registration.name, opened.get_database())
		result.diagnostics.merge(registered.diagnostics)
		if not registered.is_successful() \
				or registration.storage_backend_id != GDSQLStorageBackendIds.IN_MEMORY:
			continue
		var target := _create_in_memory_checkpoint_target(
			registration,
			opened.get_database(),
		)
		var policy := checkpoint_policies.get(
			registration.name,
			default_checkpoint_policy \
			if default_checkpoint_policy != null \
			else GDSQLCheckpointPolicy.manual(),
		) as GDSQLCheckpointPolicy
		var persistence_registration := persistence.register(
			registration.name,
			target,
			policy,
		)
		result.diagnostics.merge(persistence_registration.diagnostics)
	for binding in snapshot.role_bindings:
		var bound := registry.bind_role(binding.role, binding.registration_name)
		result.diagnostics.merge(bound.diagnostics)
	if not result.is_successful():
		return result
	var model_context := GDSQLModelContext.new(GDSQLModelRegistry.new(registry))
	var configured_models := GDSQLModels.configure(model_context)
	result.diagnostics.merge(configured_models.diagnostics)
	if result.is_successful():
		result.value = GDSQLRuntimeSession.new(registry, model_context, persistence)
	return result


## Builds or reuses effective content and replaces the active content role only
## after the candidate cache database has opened successfully.
static func activate_effective_content(
		runtime: GDSQLRuntimeSession,
		cache_manager: GDSQLContentCacheManager,
		ordered_packages: Array[GDSQLContentPackageSource],
		source_database_name: StringName = GDSQLContentOverlayLoader.DEFAULT_SOURCE_DATABASE,
		effective_database_name: StringName = GDSQLContentOverlayLoader.DEFAULT_EFFECTIVE_DATABASE,
		registration_name: StringName = &"effective_content",
) -> GDSQLContentActivationResult:
	var result := GDSQLContentActivationResult.new()
	if runtime == null or cache_manager == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_ACTIVATION_DEPENDENCY_REQUIRED",
				"Content activation requires a runtime session and cache manager.",
			),
		)
		return result
	var cached := cache_manager.ensure_cache(
		ordered_packages,
		source_database_name,
		effective_database_name,
	)
	result.cache_result = cached
	result.diagnostics.merge(cached.diagnostics)
	if not cached.is_successful():
		return result
	var opened := GDSQLDatabase.open(effective_database_name, cached.cache_root)
	result.diagnostics.merge(opened.diagnostics)
	if not opened.is_successful():
		return result
	var replaced := runtime.get_database_registry().replace_role_database(
		GDSQLDatabaseRegistry.CONTENT_ROLE,
		registration_name,
		opened.get_database(),
	)
	result.diagnostics.merge(replaced.diagnostics)
	if result.is_successful():
		result.complete(opened.get_database(), cached)
	return result


static func create_default(settings: Variant = null) -> GDSQLDatabaseContext:
	var data_root := _resolve_data_root(settings)
	var path_resolver := GDSQLDatabasePathResolver.new(data_root)
	var cache := GDSQLConfigFileCache.new()
	var codec := GDSQLGodotVariantCodec.new()
	var storage: GDSQLTableStorage = GDSQLConfigFileTableStorage.new(path_resolver, cache, codec)
	return _create_context(storage, path_resolver, cache, codec)


## Creates a runtime with ConfigFile catalog metadata and authoritative
## in-memory table rows. The returned context owns the storage instance.
static func create_in_memory(settings: Variant = null) -> GDSQLDatabaseContext:
	var data_root := _resolve_data_root(settings)
	var path_resolver := GDSQLDatabasePathResolver.new(data_root)
	var cache := GDSQLConfigFileCache.new()
	var codec := GDSQLGodotVariantCodec.new()
	return _create_context(
		GDSQLInMemoryTableStorage.new(),
		path_resolver,
		cache,
		codec,
	)


## Opens a registered database through its selected storage composition.
##
## In-memory registrations hydrate their authoritative rows from the durable
## ConfigFile representation and begin with no dirty tables.
static func open_registration(
		registration: GDSQLDatabaseRegistration,
) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	if registration == null:
		return _database_error(
			&"GDSQL_DATABASE_REGISTRATION_REQUIRED",
			"A database registration is required.",
		)
	if registration.database_name == &"" or registration.data_root.is_empty():
		return _database_error(
			&"GDSQL_DATABASE_REGISTRATION_INVALID",
			"Registration requires a database name and data root.",
		)
	if not GDSQLStorageBackendIds.is_valid(registration.storage_backend_id):
		return _database_error(
			&"GDSQL_STORAGE_BACKEND_ID_INVALID",
			"Unknown storage backend '%s'." % registration.storage_backend_id,
		)
	var context: GDSQLDatabaseContext
	match registration.storage_backend_id:
		GDSQLStorageBackendIds.CONFIG_FILE:
			context = create_default(registration.data_root)
		GDSQLStorageBackendIds.IN_MEMORY:
			context = create_in_memory(registration.data_root)
		_:
			return _database_error(
				&"GDSQL_STORAGE_BACKEND_UNAVAILABLE",
				"Storage backend '%s' is not implemented." \
						% registration.storage_backend_id,
			)
	var database_definition := context.catalog.get_database(
		registration.database_name,
	)
	if database_definition == null:
		return _database_error(
			&"GDSQL_DATABASE_NOT_FOUND",
			"Database '%s' is not registered." % registration.database_name,
		)
	if registration.storage_backend_id == GDSQLStorageBackendIds.IN_MEMORY:
		var hydration := _hydrate_in_memory(
			context,
			registration.data_root,
			database_definition,
		)
		if not hydration.is_successful():
			result.diagnostics.merge(hydration.diagnostics)
			return result
	result.value = GDSQLDatabase.new(registration.database_name, context)
	return result


static func _hydrate_in_memory(
		context: GDSQLDatabaseContext,
		data_root: String,
		database: GDSQLDatabaseDefinition,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var resolver := GDSQLDatabasePathResolver.new(data_root)
	var durable := GDSQLConfigFileTableStorage.new(
		resolver,
		GDSQLConfigFileCache.new(),
		GDSQLGodotVariantCodec.new(),
	)
	var memory := context.storage as GDSQLInMemoryTableStorage
	for table in database.tables:
		var snapshot := durable.read_table(table, null)
		if snapshot == null:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_STORAGE_TABLE_UNREADABLE",
					"Could not hydrate table '%s.%s'." \
							% [database.name, table.name],
				),
			)
			return result
		var loaded := memory.load_table(table, snapshot.rows)
		result.diagnostics.merge(loaded.diagnostics)
		if not loaded.is_successful():
			return result
	result.value = true
	return result


static func _create_in_memory_checkpoint_target(
		registration: GDSQLDatabaseRegistration,
		database: GDSQLDatabase,
) -> GDSQLInMemoryCheckpointTarget:
	var resolver := GDSQLDatabasePathResolver.new(registration.data_root)
	var durable := GDSQLConfigFileTableStorage.new(
		resolver,
		GDSQLConfigFileCache.new(),
		GDSQLGodotVariantCodec.new(),
	)
	return GDSQLInMemoryCheckpointTarget.new(
		database.context.storage as GDSQLInMemoryTableStorage,
		durable,
	)


static func _create_context(
		storage: GDSQLTableStorage,
		path_resolver: GDSQLDatabasePathResolver,
		cache: GDSQLConfigFileCache,
		codec: GDSQLGodotVariantCodec,
) -> GDSQLDatabaseContext:
	var catalog: GDSQLCatalogService = GDSQLConfigFileCatalogService.new(path_resolver, codec)
	var catalog_administration: GDSQLCatalogAdministrationService = \
			GDSQLConfigFileCatalogAdministrationService.new(
				path_resolver,
				catalog,
				cache,
				codec,
			)
	var transactions := GDSQLTransactionManager.new(storage)
	var function_catalog := FunctionCatalog.new()
	var function_registry := GDSQLQueryFunctionRegistry.new(function_catalog)
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
		GDSQLDefaultQueryPlanner.new(storage.get_capabilities()),
		GDSQLDefaultQueryExecutor.new(),
		execution_context,
	)


static func _resolve_data_root(settings: Variant) -> String:
	var data_root := "res://data"
	if settings is String:
		data_root = settings
	elif settings is Dictionary:
		data_root = settings.get("data_root", data_root)
	return data_root


static func _database_error(
		code: StringName,
		message: String,
) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
