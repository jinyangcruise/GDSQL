class_name GDSQLConfigFileMigrationSimulator
extends GDSQLMigrationSimulator
## Runs ordered previews against an isolated copy of one ConfigFile database.

const SIMULATION_ROOT := "user://.gdsql/migration_simulations"

var _source_paths: GDSQLDatabasePathResolver
var _simulation_index := 0


class SimulationServices:
	extends RefCounted

	var administration: GDSQLCatalogAdministrationService
	var validator: GDSQLQueryValidator
	var planner: GDSQLQueryPlanner
	var executor: GDSQLQueryExecutor
	var execution_context: GDSQLExecutionContext


	func _init(
			catalog_administration: GDSQLCatalogAdministrationService,
			query_validator: GDSQLQueryValidator,
			query_planner: GDSQLQueryPlanner,
			query_executor: GDSQLQueryExecutor,
			context: GDSQLExecutionContext,
	) -> void:
		administration = catalog_administration
		validator = query_validator
		planner = query_planner
		executor = query_executor
		execution_context = context


func _init(source_paths: GDSQLDatabasePathResolver) -> void:
	assert(source_paths != null)
	_source_paths = source_paths


func preview(
		database_name: StringName,
		migration: GDSQLMigrationDefinition,
		ledger_revision: int,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _source_paths.is_valid_name(database_name) or migration == null \
			or not migration.is_valid() or migration.steps.size() < 2 \
			or ledger_revision < 0:
		return _error(
			result,
			&"GDSQL_MIGRATION_SIMULATION_INPUT_INVALID",
			"Migration simulation requires a valid multi-step migration and database.",
		)
	var simulation_root := _next_simulation_root(database_name, migration.migration_id)
	var prepared := _prepare_copy(simulation_root, database_name)
	result.diagnostics.merge(prepared.diagnostics)
	if prepared.is_successful():
		var services := _create_services(
			GDSQLDatabasePathResolver.new(simulation_root.path_join("data")),
		)
		var simulated := _simulate(
			services,
			database_name,
			migration,
			ledger_revision,
		)
		result.diagnostics.merge(simulated.diagnostics)
		if simulated.is_successful():
			result.value = simulated.get_value()
	var cleanup_error := _remove_tree(simulation_root)
	if cleanup_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MIGRATION_SIMULATION_CLEANUP_PENDING",
				"Migration preview completed but its isolated temporary copy could not be removed.",
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
	return result


func _simulate(
		services: SimulationServices,
		database_name: StringName,
		migration: GDSQLMigrationDefinition,
		ledger_revision: int,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var previews: Array[GDSQLMigrationStepPreview] = []
	for step in migration.steps:
		if step is GDSQLSchemaMigrationStep:
			var schema_step := step as GDSQLSchemaMigrationStep
			var previewed := _preview_schema(
				services.administration,
				database_name,
				schema_step,
			)
			result.diagnostics.merge(previewed.diagnostics)
			if not previewed.is_successful():
				return result
			var change_plan := previewed.get_value() as GDSQLCatalogChangePlan
			if change_plan == null:
				return _error(
					result,
					&"GDSQL_MIGRATION_CATALOG_PLAN_MISSING",
					"Catalog simulation did not produce a schema change plan.",
				)
			previews.append(
				GDSQLMigrationStepPreview.for_schema(schema_step, change_plan),
			)
			var applied := services.administration.apply_change_plan(change_plan) \
					as GDSQLCatalogOperationResult
			result.diagnostics.merge(applied.diagnostics)
			if not applied.is_successful():
				return result
			continue
		var data_step := step as GDSQLDataMigrationStep
		if data_step == null:
			return _error(
				result,
				&"GDSQL_MIGRATION_STEP_UNSUPPORTED",
				"Migration simulation encountered an unsupported step type.",
			)
		var executed := _execute_data_step(services, database_name, data_step)
		result.diagnostics.merge(executed.diagnostics)
		if not executed.is_successful():
			return result
		previews.append(
			GDSQLMigrationStepPreview.for_data(
				data_step,
				int(executed.statistics.get("affected_rows", 0)),
			),
		)
	result.value = GDSQLMigrationStepPlan.for_steps(
		database_name,
		migration,
		previews,
		ledger_revision,
	)
	return result


func _preview_schema(
		administration: GDSQLCatalogAdministrationService,
		database_name: StringName,
		step: GDSQLSchemaMigrationStep,
) -> GDSQLOperationResult:
	match step.kind:
		GDSQLSchemaMigrationStep.Kind.ALTER_TABLE:
			return administration.preview_alter_table(
				database_name,
				step.table_name,
				step.alterations,
			)
		GDSQLSchemaMigrationStep.Kind.CREATE_TABLE:
			return administration.preview_create_table(
				database_name,
				step.table_definition,
			)
		GDSQLSchemaMigrationStep.Kind.RENAME_TABLE:
			return administration.preview_rename_table(
				database_name,
				step.table_name,
				step.new_table_name,
			)
		GDSQLSchemaMigrationStep.Kind.DROP_TABLE:
			return administration.preview_drop_table(database_name, step.table_name)
	return _error(
		GDSQLOperationResult.new(),
		&"GDSQL_MIGRATION_STEP_UNSUPPORTED",
		"Migration uses an unsupported catalog lifecycle operation.",
	)


func _execute_data_step(
		services: SimulationServices,
		database_name: StringName,
		step: GDSQLDataMigrationStep,
) -> GDSQLQueryExecutionResult:
	var validation := services.validator.validate(step.to_query(database_name)) \
			as GDSQLQueryValidationResult
	if not validation.is_valid():
		var invalid := GDSQLQueryExecutionResult.new()
		invalid.diagnostics.merge(validation.diagnostics)
		return invalid
	var planning := services.planner.create_plan(validation.bound_query) \
			as GDSQLQueryPlanningResult
	if not planning.is_successful() or planning.plan == null:
		var unplanned := GDSQLQueryExecutionResult.new()
		unplanned.diagnostics.merge(planning.diagnostics)
		return unplanned
	return services.executor.execute(planning.plan, services.execution_context)


func _create_services(paths: GDSQLDatabasePathResolver) -> SimulationServices:
	var cache := GDSQLConfigFileCache.new()
	var codec := GDSQLGodotVariantCodec.new()
	var storage := GDSQLConfigFileTableStorage.new(paths, cache, codec)
	var catalog := GDSQLConfigFileCatalogService.new(paths, codec)
	var administration := GDSQLConfigFileCatalogAdministrationService.new(
		paths,
		catalog,
		cache,
		codec,
	)
	var transactions := GDSQLTransactionManager.new(
		storage,
		GDSQLForeignKeyConstraintValidator.new(catalog, storage),
	)
	var function_catalog := GDSQLQueryFunctionCatalog.new()
	var function_registry := GDSQLQueryFunctionRegistry.new(function_catalog)
	var validator := GDSQLDefaultQueryValidator.new(catalog, function_catalog)
	var planner := GDSQLDefaultQueryPlanner.new(storage.get_capabilities())
	var executor := GDSQLDefaultQueryExecutor.new()
	var execution_context := GDSQLExecutionContext.new(
		catalog,
		storage,
		transactions,
		GDSQLExpressionEvaluator.new(function_registry),
		function_registry,
		GDSQLQueryCancellationToken.new(),
	)
	return SimulationServices.new(
		administration,
		validator,
		planner,
		executor,
		execution_context,
	)


func _prepare_copy(
		simulation_root: String,
		database_name: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var source_path := _source_paths.resolve_database_path(database_name)
	if not _directory_exists(source_path):
		return _error(
			result,
			&"GDSQL_MIGRATION_SIMULATION_DATABASE_NOT_FOUND",
			"Database '%s' cannot be simulated because its directory is missing." \
					% database_name,
		)
	var data_root := simulation_root.path_join("data")
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(data_root),
	)
	if directory_error != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_SIMULATION_DIRECTORY_UNAVAILABLE",
			"Could not create isolated migration preview storage.",
		)
	var target_paths := GDSQLDatabasePathResolver.new(data_root)
	var copy_error := _copy_tree(
		source_path,
		target_paths.resolve_database_path(database_name),
	)
	if copy_error != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_SIMULATION_COPY_FAILED",
			"Could not copy database '%s' into isolated preview storage." % database_name,
		)
	var registry := ConfigFile.new()
	registry.set_value(
		String(database_name),
		"path",
		target_paths.resolve_database_path(database_name),
	)
	if registry.save(target_paths.resolve_catalog_path()) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_SIMULATION_CATALOG_FAILED",
			"Could not register the isolated migration preview database.",
		)
	result.value = true
	return result


func _next_simulation_root(database_name: StringName, migration_id: String) -> String:
	_simulation_index += 1
	return SIMULATION_ROOT.path_join(
		"%s_%s_%d_%d" % [
			database_name,
			migration_id.sha256_text().left(12),
			Time.get_ticks_usec(),
			_simulation_index,
		],
	)


func _copy_tree(source: String, destination: String) -> Error:
	var source_directory := DirAccess.open(source)
	if source_directory == null:
		return ERR_CANT_OPEN
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(destination),
	)
	if directory_error != OK:
		return directory_error
	for file_name in source_directory.get_files():
		var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source.path_join(file_name)),
			ProjectSettings.globalize_path(destination.path_join(file_name)),
		)
		if copy_error != OK:
			return copy_error
	for directory_name in source_directory.get_directories():
		var copy_error := _copy_tree(
			source.path_join(directory_name),
			destination.path_join(directory_name),
		)
		if copy_error != OK:
			return copy_error
	return OK


func _remove_tree(path: String) -> Error:
	if not _directory_exists(path):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name in directory.get_files():
		var error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path.path_join(file_name)),
		)
		if error != OK:
			return error
	for directory_name in directory.get_directories():
		var error := _remove_tree(path.path_join(directory_name))
		if error != OK:
			return error
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _directory_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
