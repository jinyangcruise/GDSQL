class_name GDSQLQueryGraphEditorTest
extends GdUnitTestSuite

const QUERY_GRAPH_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/graph_editor.tscn"
)


func test_select_node_defaults_to_the_requested_database_and_table() -> void:
	var editor := auto_free(QUERY_GRAPH_SCENE.instantiate()) \
			as GDSQLQueryGraphEditor
	add_child(editor)
	await await_idle_frame()
	var inspections := _create_inspections()

	editor.configure(inspections, &"content_registration", &"items")

	assert_str(String(editor.get_selected_registration())) \
			.is_equal("content_registration")
	assert_str(String(editor.get_selected_database())).is_equal("content")
	assert_str(String(editor.get_selected_table())).is_equal("items")


func test_select_node_exposes_one_table_rows_output_port() -> void:
	var editor := auto_free(QUERY_GRAPH_SCENE.instantiate()) \
			as GDSQLQueryGraphEditor
	add_child(editor)
	await await_idle_frame()
	editor.configure(_create_inspections(), &"save_registration", &"state")

	var select_operation := editor.get_node("%SelectOperation") as GraphNode
	assert_int(select_operation.get_output_port_count()).is_equal(1)
	assert_int(select_operation.get_output_port_type(0)).is_equal(0)


func _create_inspections() -> Array[GDSQLDatabaseInspection]:
	var content := GDSQLDatabaseInspection.new(
		GDSQLDatabaseRegistration.new(
			&"content_registration",
			&"content",
			"res://data",
		),
		true,
	)
	content.tables.append(
		GDSQLTableInspection.new(&"heroes", true, true, 4, 3, 0),
	)
	content.tables.append(
		GDSQLTableInspection.new(&"items", true, true, 7, 5, 1),
	)
	var save := GDSQLDatabaseInspection.new(
		GDSQLDatabaseRegistration.new(
			&"save_registration",
			&"save",
			"user://gdsql/saves/slot_1",
		),
		true,
	)
	save.tables.append(
		GDSQLTableInspection.new(&"state", true, true, 1, 2, 0),
	)
	return [content, save]
