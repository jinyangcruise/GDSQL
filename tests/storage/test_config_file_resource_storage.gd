class_name GDSQLConfigFileResourceStorageTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_resource_storage_%d" % _test_index)


func test_owned_and_referenced_resources_round_trip_with_distinct_storage() -> void:
	var referenced_icon := load(REFERENCED_ICON_PATH) as Resource
	var table := _resource_table(referenced_icon)
	var database := TestDatabase.create_database(_data_root, table)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 3.0, 4.0)

	var inserted := database.insert(
		&"assets",
		{&"id": 1, &"mesh": mesh, &"icon": referenced_icon},
	)
	assert_bool(inserted.is_successful()).is_true()

	var table_text := FileAccess.get_file_as_string(
		_data_root.path_join("game_config/tables/assets.cfg"),
	)
	assert_bool(table_text.contains("Object(BoxMesh")).is_true()
	assert_bool(table_text.contains("resource_reference")).is_true()
	assert_bool(table_text.contains(REFERENCED_ICON_PATH)).is_true()
	assert_bool(table_text.contains("PackedByteArray")).is_false()

	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var reopened_table := reopened.context.catalog.get_table(&"game_config", &"assets")
	assert_int(reopened_table.get_column(&"mesh").resource_ownership) \
		.is_equal(GDSQLResourceOwnership.Mode.OWNED)
	assert_int(reopened_table.get_column(&"icon").resource_ownership) \
		.is_equal(GDSQLResourceOwnership.Mode.REFERENCED)
	var selected := reopened.execute(reopened.query().select().from_table(&"assets").build())
	assert_bool(selected.is_successful()).is_true()
	assert_object(selected.rows[0].get_value(&"mesh")).is_instanceof(BoxMesh)
	assert_object(selected.rows[0].get_value(&"icon")).is_same(referenced_icon)
	assert_bool(
		(selected.rows[0].get_value(&"mesh") as BoxMesh).size.is_equal_approx(
			Vector3(2.0, 3.0, 4.0),
		),
	).is_true()


func test_referenced_resource_requires_a_saved_asset_path() -> void:
	var prototype := BoxMesh.new()
	var table := GDSQLTableDefinition.new(&"assets", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var mesh_column := GDSQLColumnDefinition.new(&"mesh", TYPE_OBJECT, false)
	mesh_column.resource_type = GDSQLResourceTypeConstraint.from_resource(prototype)
	mesh_column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	table.add_column(mesh_column)
	var database := TestDatabase.create_database(_data_root, table)

	var inserted := database.insert(&"assets", {&"id": 1, &"mesh": prototype})

	assert_bool(inserted.is_successful()).is_false()
	assert_str(String(inserted.diagnostics.entries[0].code)) \
		.is_equal("GDSQL_STORAGE_RESOURCE_REFERENCE_PATH_REQUIRED")


func _resource_table(referenced_icon: Resource) -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"assets", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var mesh_column := GDSQLColumnDefinition.new(&"mesh", TYPE_OBJECT, false)
	mesh_column.resource_type = GDSQLResourceTypeConstraint.from_resource(BoxMesh.new())
	mesh_column.resource_ownership = GDSQLResourceOwnership.Mode.OWNED
	table.add_column(mesh_column)
	var icon_column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	icon_column.resource_type = GDSQLResourceTypeConstraint.from_resource(referenced_icon)
	icon_column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	table.add_column(icon_column)
	return table
