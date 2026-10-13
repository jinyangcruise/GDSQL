class_name GDSQLMcpSchemaAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _root: String
var _database: GDSQLDatabase
var _service: GDSQLMcpAuthoringService
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_root = create_temp_dir(
		"gdsql_mcp_schema_authoring_%d_%d" % [_test_index, Time.get_ticks_usec()],
	)
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true)) \
			.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	_database = TestDatabase.create_database(_root, heroes, &"content")
	var registration := GDSQLDatabaseRegistration.new(&"content", &"content", _root)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign([registration])
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(_root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	_service = GDSQLMcpAuthoringService.new(workbench)


func test_create_table_requires_preview_and_one_use_confirmation() -> void:
	var preview := _service.preview_schema_mutation(
		{
			"operation": "create_table",
			"registration": "content",
			"table": {
				"name": "loadouts",
				"primary_key": "id",
				"columns": [
					{
						"name": "id",
						"type": "int",
						"nullable": false,
						"unique": true,
						"auto_increment": true,
					},
					{ "name": "hero_id", "type": "int", "nullable": false },
					{ "name": "label", "type": "string", "default": "New" },
				],
				"indexes": [
					{ "name": "loadouts_by_label", "columns": ["label"] },
				],
				"foreign_keys": [
					{
						"name": "loadouts_hero",
						"column": "hero_id",
						"referenced_table": "heroes",
						"referenced_column": "id",
					},
				],
			},
		},
	)

	assert_bool(preview.is_successful()).is_true()
	assert_object(_table(&"loadouts")).is_null()
	var payload := preview.get_value() as Dictionary
	var handle: String = payload["data"]["confirmation_handle"]
	assert_bool(_service.commit_schema_mutation(handle, false).is_successful()).is_false()
	var committed := _service.commit_schema_mutation(handle, true)
	assert_bool(committed.is_successful()).is_true()
	assert_object(_table(&"loadouts")).is_not_null()
	assert_bool(_service.commit_schema_mutation(handle, true).is_successful()).is_false()


func test_alter_table_supports_columns_indexes_and_foreign_keys() -> void:
	assert_bool(
		_database.create_table(
			GDSQLTableDefinition.new(&"classes", &"id") \
					.add_column(
						GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
					),
		).is_successful(),
	).is_true()
	var preview := _service.preview_schema_mutation(
		{
			"operation": "alter_table",
			"registration": "content",
			"table": "heroes",
			"alterations": [
				{
					"kind": "add_column",
					"column": { "name": "class_id", "type": "int", "nullable": true },
				},
				{
					"kind": "add_column",
					"column": { "name": "slug", "type": "string", "nullable": true },
				},
				{
					"kind": "add_index",
					"index": {
						"name": "heroes_by_slug",
						"columns": ["slug"],
						"unique": true,
					},
				},
				{
					"kind": "add_foreign_key",
					"foreign_key": {
						"name": "heroes_class",
						"column": "class_id",
						"referenced_table": "classes",
						"referenced_column": "id",
					},
				},
			],
		},
	)

	assert_bool(preview.is_successful()).is_true()
	assert_bool(
		_service.commit_schema_mutation(
			preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	var heroes := _table(&"heroes")
	assert_object(heroes.get_column(&"slug")).is_not_null()
	assert_object(heroes.get_index(&"heroes_by_slug")).is_not_null()
	assert_object(heroes.get_foreign_key(&"heroes_class")).is_not_null()


func test_rename_and_drop_table_use_canonical_destructive_plans() -> void:
	var renamed := _service.preview_schema_mutation(
		{
			"operation": "rename_table",
			"registration": "content",
			"table": "heroes",
			"new_name": "characters",
		},
	)
	assert_bool(renamed.is_successful()).is_true()
	assert_bool(
		_service.commit_schema_mutation(
			renamed.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_object(_table(&"characters")).is_not_null()

	var dropped := _service.preview_schema_mutation(
		{
			"operation": "drop_table",
			"registration": "content",
			"table": "characters",
		},
	)
	assert_bool(dropped.is_successful()).is_true()
	assert_bool(dropped.get_value()["data"]["destructive"]).is_true()
	assert_bool(
		_service.commit_schema_mutation(
			dropped.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_object(_table(&"characters")).is_null()


func test_schema_plan_is_rejected_after_an_external_catalog_change() -> void:
	var preview := _service.preview_schema_mutation(
		{
			"operation": "alter_table",
			"registration": "content",
			"table": "heroes",
			"alterations": [{ "kind": "drop_column", "column": "name" }],
		},
	)
	assert_bool(preview.is_successful()).is_true()
	assert_bool(
		_database.alter_table(
			&"heroes",
			[
				GDSQLTableAlteration.add_column(
					GDSQLColumnDefinition.new(&"level", TYPE_INT, true),
				),
			],
		).is_successful(),
	).is_true()

	var committed := _service.commit_schema_mutation(
		preview.get_value()["data"]["confirmation_handle"],
		true,
	)

	assert_bool(committed.is_successful()).is_false()
	assert_str(String(committed.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_CHANGE_PLAN_STALE",
	)


func test_resource_columns_require_explicit_valid_storage_semantics() -> void:
	var invalid := _service.preview_schema_mutation(
		{
			"operation": "alter_table",
			"registration": "content",
			"table": "heroes",
			"alterations": [
				{
					"kind": "add_column",
					"column": {
						"name": "portrait",
						"type": "resource",
						"resource": { "class": "Texture2D" },
					},
				},
			],
		},
	)
	assert_bool(invalid.is_successful()).is_false()
	assert_str(String(invalid.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
	)

	var valid := _service.preview_schema_mutation(
		{
			"operation": "alter_table",
			"registration": "content",
			"table": "heroes",
			"alterations": [
				{
					"kind": "add_column",
					"column": {
						"name": "portrait",
						"type": "resource",
						"resource": {
							"class": "Texture2D",
							"ownership": "referenced",
						},
					},
				},
			],
		},
	)
	assert_bool(valid.is_successful()).is_true()


func _table(table_name: StringName) -> GDSQLTableDefinition:
	var opened := GDSQLDatabase.open(&"content", _root)
	assert_bool(opened.is_successful()).is_true()
	var database := opened.get_database()
	return database.context.catalog.get_table(database.database_name, table_name)
