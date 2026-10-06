class_name GDSQLResourceMaterializationTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"

var _data_root: String
var _test_index := 0


class CountingResolver:
	extends GDSQLResourceResolver

	var calls := 0
	var resolved_resource: Resource
	var failure_code: StringName


	func _init(resource: Resource, error_code: StringName = &"") -> void:
		resolved_resource = resource
		failure_code = error_code


	func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult:
		calls += 1
		var result := GDSQLOperationResult.new()
		if failure_code != &"":
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					failure_code,
					"The test asset could not be loaded.",
					GDSQLQueryDiagnostic.Severity.ERROR,
					null,
					reference,
				),
			)
			return result
		result.value = resolved_resource
		return result


class AssetModel extends GDSQLContentModel:
	var id: int
	var name: String
	var icon: Texture2D


	func table_name() -> StringName:
		return &"assets"


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_resource_materialization_%d" % _test_index)


func test_unrelated_projection_and_count_do_not_materialize_reference() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var names := database.execute(
		database.table(&"assets").select().column(&"name").build(),
	)
	var count := database.execute(
		database.table(&"assets").select().count(null, &"total").build(),
	)

	assert_bool(names.is_successful()).is_true()
	assert_str(names.rows[0].get_value(&"name")).is_equal("Key")
	assert_bool(count.is_successful()).is_true()
	assert_int(count.rows[0].get_value(&"total")).is_equal(1)
	assert_int(resolver.calls).is_zero()


func test_projected_reference_materializes_once_and_remains_a_resource() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var selected := database.execute(
		database.table(&"assets").select().column(&"icon").build(),
	)

	assert_bool(selected.is_successful()).is_true()
	assert_object(selected.rows[0].get_value(&"icon")).is_same(icon)
	assert_int(selected.statistics.get("resources_materialized", 0)).is_equal(1)
	assert_int(resolver.calls).is_equal(1)


func test_pushed_window_does_not_materialize_skipped_resource_rows() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	assert_bool(
		database.insert(
			&"assets",
			{&"id": 2, &"name": "Second key", &"icon": icon},
		).is_successful(),
	).is_true()
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var selected := database.execute(
		database.table(&"assets")
		.select()
		.column(&"icon")
		.offset(1)
		.limit(1)
		.build(),
	)

	assert_bool(selected.is_successful()).is_true()
	assert_object(selected.rows[0].get_value(&"icon")).is_same(icon)
	assert_bool(selected.statistics["scan_window_pushed"]).is_true()
	assert_int(selected.statistics["scan_rows_pruned"]).is_equal(1)
	assert_int(selected.statistics["resources_materialized"]).is_equal(1)
	assert_int(resolver.calls).is_equal(1)


func test_deferred_query_returns_unloaded_handle_without_resolving_asset() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var selected := database.execute(
		database.table(&"assets").select()
		.column(&"icon")
		.where(GDSQLExpr.column(&"name").equals("Key"))
		.build(),
		GDSQLQueryExecutionOptions.deferred_resources(),
	)
	var scope := selected.create_resource_prefetch_scope()
	var handle := scope.get_handles()[0]

	assert_bool(selected.is_successful()).is_true()
	assert_object(handle).is_not_null()
	assert_int(scope.get_handles().size()).is_equal(1)
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)
	assert_int(selected.statistics.get("resource_handles_created", 0)).is_equal(1)
	assert_int(resolver.calls).is_zero()
	assert_object(handle.load().get_value()).is_same(icon)
	assert_int(resolver.calls).is_equal(1)


func test_deferred_query_rejects_resource_dependent_expression() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var selected := database.execute(
		database.table(&"assets").select()
		.where(GDSQLExpr.column(&"icon").equals(icon))
		.build(),
		GDSQLQueryExecutionOptions.deferred_resources(),
	)

	assert_bool(selected.is_successful()).is_false()
	assert_str(String(selected.diagnostics.entries[0].code)).is_equal(
		"GDSQL_DEFERRED_RESOURCE_EXPRESSION_UNSUPPORTED",
	)
	assert_int(resolver.calls).is_zero()


func test_deferred_model_retains_handle_and_updates_typed_property_after_load() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(icon)
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)
	var database_registry := GDSQLDatabaseRegistry.new()
	database_registry.register(&"active", database)
	database_registry.bind_role(GDSQLDatabaseRegistry.CONTENT_ROLE, &"active")
	var model_registry := GDSQLModelRegistry.new(database_registry)
	assert_bool(model_registry.register(AssetModel).is_successful()).is_true()
	var model_context := GDSQLModelContext.new(model_registry)

	var selected := model_context.query(AssetModel).defer_resources().first()
	var model := selected.get_value() as AssetModel
	var handle := model.get_resource_handle(&"icon")
	var scope := model.create_resource_prefetch_scope()

	assert_bool(selected.is_successful()).is_true()
	assert_object(model).is_not_null()
	assert_object(model.icon).is_null()
	assert_bool(model.has_resource_handle(&"icon")).is_true()
	assert_int(resolver.calls).is_zero()
	assert_object(handle.load().get_value()).is_same(icon)
	assert_object(model.icon).is_same(icon)
	scope.release()
	assert_object(model.icon).is_null()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)


func test_failed_materialization_reports_row_and_column_context() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var database := _create_database(icon)
	var resolver := CountingResolver.new(null, &"TEST_RESOURCE_MISSING")
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)

	var selected := database.execute(
		database.table(&"assets").select().column(&"icon").build(),
	)

	assert_bool(selected.is_successful()).is_false()
	assert_str(String(selected.diagnostics.entries[0].code)).is_equal(
		"TEST_RESOURCE_MISSING",
	)
	assert_str(selected.diagnostics.entries[0].message).contains(
		"game_config.assets row '1' column 'icon'",
	)


func _create_database(icon: Resource) -> GDSQLDatabase:
	var table := GDSQLTableDefinition.new(&"assets", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var icon_column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	icon_column.resource_type = GDSQLResourceTypeConstraint.from_resource(icon)
	icon_column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	table.add_column(icon_column)
	var database := TestDatabase.create_database(_data_root, table)
	var inserted := database.insert(
		&"assets",
		{&"id": 1, &"name": "Key", &"icon": icon},
	)
	assert_bool(inserted.is_successful()).is_true()
	return database
