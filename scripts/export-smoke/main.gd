extends Node
## Verifies the packaged runtime API without loading the editor plugin.

const DATABASE_NAME := &"runtime_smoke"
const TABLE_NAME := &"entries"


func _ready() -> void:
	if DirAccess.open("res://addons/gdsql/editor") != null:
		_fail("editor subtree exclusion")
		return
	var addon_directory := DirAccess.open("res://addons/gdsql")
	if addon_directory == null:
		_fail("runtime addon inclusion")
		return
	for file_name in addon_directory.get_files():
		if file_name.begins_with("plugin.gd") \
				or file_name == "plugin.cfg":
			_fail("editor plugin exclusion")
			return
	var database_result := GDSQLDatabase.create(DATABASE_NAME, "user://data")
	if not database_result.is_successful():
		_fail("database creation")
		return
	var database := database_result.get_database()
	var table := GDSQLTableDefinition.new(TABLE_NAME, &"id")
	table.add_column(
		GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
	)
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	if not database.create_table(table).is_successful():
		_fail("table creation")
		return
	if not database.insert(TABLE_NAME, { &"name": "exported runtime" }).is_successful():
		_fail("row insertion")
		return
	var reopened_result := GDSQLDatabase.open(DATABASE_NAME, "user://data")
	if not reopened_result.is_successful():
		_fail("database reopen")
		return
	var reopened := reopened_result.get_database()
	var selected := reopened.execute(
		reopened.query().table(TABLE_NAME).select().build(),
	)
	if not selected.is_successful() \
			or selected.rows.size() != 1 \
			or selected.rows[0].get_value(&"name") != "exported runtime":
		_fail("persisted query")
		return
	print("GDSQL_EXPORT_SMOKE_OK")
	get_tree().quit(0)


func _fail(stage: String) -> void:
	push_error("GDSQL exported runtime smoke failed during %s." % stage)
	get_tree().quit(1)
