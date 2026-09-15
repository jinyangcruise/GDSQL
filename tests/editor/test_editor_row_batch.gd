class_name GDSQLEditorRowBatchTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String


func before_test() -> void:
	_data_root = create_temp_dir("gdsql_editor_row_batch")


func test_builds_and_executes_atomic_updates() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var table := database.context.catalog.get_table(database.database_name, &"heroes")
	var updates: Array[Dictionary] = [
		{
			"primary_key": 1,
			"before_values": {&"name": "Knight"},
			"values": {&"name": "Paladin"},
		},
		{
			"primary_key": 2,
			"before_values": {&"name": "Mage"},
			"values": {&"name": "Wizard"},
		},
	]

	var planned := GDSQLEditorRowBatch.build_updates(table, updates)
	var batch := planned.get_value() as GDSQLEditorRowBatch

	assert_bool(planned.is_successful()).is_true()
	assert_int(batch.operation).is_equal(GDSQLEditorRowBatch.Operation.UPDATE)
	assert_int(batch.row_count).is_equal(2)
	assert_bool(batch.execute(database).is_successful()).is_true()
	var rows := database.execute(
		database.query().select().from_table(&"heroes").order_by_column(&"id").build(),
	)
	assert_str(String(rows.rows[0].get_value(&"name"))).is_equal("Paladin")
	assert_str(String(rows.rows[1].get_value(&"name"))).is_equal("Wizard")
	var entry := batch.create_history_entry(&"project")
	assert_object(entry).is_not_null()
	assert_str(String(entry.before_rows[0].get_value(&"name"))).is_equal("Knight")
	assert_str(String(entry.after_rows[1].get_value(&"name"))).is_equal("Wizard")

	var inverse_updates: Array[Dictionary] = [
		{"primary_key": 1, "values": {&"name": "Knight"}},
		{"primary_key": 2, "values": {&"name": "Mage"}},
	]
	var inverse := GDSQLEditorRowBatch.build_updates(table, inverse_updates)
	assert_bool(inverse.is_successful()).is_true()
	assert_bool(
			(inverse.get_value() as GDSQLEditorRowBatch).execute(database).is_successful(),
	).is_true()
	rows = database.execute(
		database.query().select().from_table(&"heroes").order_by_column(&"id").build(),
	)
	assert_str(String(rows.rows[0].get_value(&"name"))).is_equal("Knight")
	assert_str(String(rows.rows[1].get_value(&"name"))).is_equal("Mage")


func test_update_without_before_values_is_not_recordable() -> void:
	var updates: Array[Dictionary] = [
		{"primary_key": 1, "values": {&"name": "Paladin"}},
	]
	var planned := GDSQLEditorRowBatch.build_updates(_table_definition(), updates)
	var batch := planned.get_value() as GDSQLEditorRowBatch

	assert_bool(planned.is_successful()).is_true()
	assert_object(batch.create_history_entry(&"project")).is_null()


func test_rejects_read_only_and_unknown_update_columns() -> void:
	var table := _table_definition()
	var updates: Array[Dictionary] = [{
		"primary_key": 1,
		"values": {&"id": 2, &"created_at": 0, &"missing": "value"},
	}]

	var result := GDSQLEditorRowBatch.build_updates(table, updates)

	assert_bool(result.is_successful()).is_false()
	assert_int(result.diagnostics.entries.size()).is_equal(3)


func test_rejects_duplicate_row_identities() -> void:
	var primary_keys: Array[Variant] = [1, 1]
	var result := GDSQLEditorRowBatch.build_deletes(
		_table_definition(),
		primary_keys,
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_EDITOR_ROW_BATCH_DUPLICATE_IDENTITY",
	)


func test_rejects_empty_batches() -> void:
	var updates: Array[Dictionary] = []
	var result := GDSQLEditorRowBatch.build_updates(_table_definition(), updates)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_EDITOR_ROW_BATCH_EMPTY",
	)


func _table_definition() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.database_name = &"content"
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.created_at())
	return table
