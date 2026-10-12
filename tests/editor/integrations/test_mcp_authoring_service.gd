class_name GDSQLMcpAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _root: String
var _registration: GDSQLDatabaseRegistration
var _database: GDSQLDatabase
var _service: GDSQLMcpAuthoringService
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_root = create_temp_dir("gdsql_mcp_authoring_%d" % _test_index)
	var table := GDSQLTableDefinition.new(&"heroes", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true)) \
			.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false, true)) \
			.add_column(GDSQLColumnDefinition.new(&"level", TYPE_INT, false))
	_database = TestDatabase.create_database(_root, table, &"content")
	TestDatabase.insert_rows(
		_database,
		[
			{ &"id": 1, &"name": "Knight", &"level": 5 },
			{ &"id": 2, &"name": "Mage", &"level": 9 },
			{ &"id": 3, &"name": "Rogue", &"level": 7 },
		],
	)
	_registration = GDSQLDatabaseRegistration.new(&"content", &"content", _root)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign([_registration])
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(_root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	_service = GDSQLMcpAuthoringService.new(workbench)


func test_query_rows_supports_structured_where_and_bound_cursor() -> void:
	var first := _service.query_rows(
		&"content",
		&"heroes",
		["id", "name", "level"],
		{
			"operator": "gte",
			"column": "level",
			"value": 5,
		},
		[{ "column": "level", "direction": "desc" }],
		"",
		2,
	)

	assert_bool(first.is_successful()).is_true()
	var payload := first.get_value() as Dictionary
	assert_array(payload["data"]["items"]).has_size(2)
	assert_str(payload["data"]["items"][0]["name"]).is_equal("Mage")
	assert_bool(payload["meta"]["truncated"]).is_true()
	var second := _service.query_rows(
		&"content",
		&"heroes",
		["id", "name", "level"],
		{ "operator": "gte", "column": "level", "value": 5 },
		[{ "column": "level", "direction": "desc" }],
		payload["meta"]["next_cursor"],
		2,
	)
	assert_bool(second.is_successful()).is_true()
	assert_int(second.get_value()["data"]["items"].size()).is_equal(1)


func test_insert_requires_preview_and_one_use_confirmation() -> void:
	var preview := _service.preview_row_mutation(
		{
			"operation": "insert",
			"registration": "content",
			"table": "heroes",
			"rows": [{ "name": "Cleric", "level": 8 }],
		},
	)

	assert_bool(preview.is_successful()).is_true()
	var handle: String = preview.get_value()["data"]["confirmation_handle"]
	assert_bool(_service.commit_row_mutation(handle, false).is_successful()).is_false()
	var committed := _service.commit_row_mutation(handle, true)
	assert_bool(committed.is_successful()).is_true()
	assert_int(committed.get_value()["data"]["affected_rows"]).is_equal(1)
	assert_bool(_service.commit_row_mutation(handle, true).is_successful()).is_false()
	var rows := _service.query_rows(
		&"content",
		&"heroes",
		[],
		{ "column": "name", "operator": "eq", "value": "Cleric" },
	)
	assert_bool(rows.is_successful()).is_true()
	assert_int(rows.get_value()["data"]["items"].size()).is_equal(1)


func test_update_handle_is_rejected_when_target_changes() -> void:
	var preview := _service.preview_row_mutation(
		{
			"operation": "update",
			"registration": "content",
			"table": "heroes",
			"rows": [{ "primary_key": 1, "values": { "level": 6 } }],
		},
	)
	assert_bool(preview.is_successful()).is_true()
	var changed := _database.execute(
		_database.table(&"heroes").update() \
				.set_value(&"level", 10) \
				.where(GDSQLExpr.column(&"id").equals(1)) \
				.build(),
	)
	assert_bool(changed.is_successful()).is_true()

	var committed := _service.commit_row_mutation(
		preview.get_value()["data"]["confirmation_handle"],
		true,
	)

	assert_bool(committed.is_successful()).is_false()
	assert_str(String(committed.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_MUTATION_STALE",
	)


func test_delete_preview_commits_atomically() -> void:
	var preview := _service.preview_row_mutation(
		{
			"operation": "delete",
			"registration": "content",
			"table": "heroes",
			"primary_keys": [2, 3],
		},
	)
	assert_bool(preview.is_successful()).is_true()
	assert_bool(
		_service.commit_row_mutation(
			preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	var rows := _service.query_rows(&"content", &"heroes")
	assert_int(rows.get_value()["data"]["items"].size()).is_equal(1)
