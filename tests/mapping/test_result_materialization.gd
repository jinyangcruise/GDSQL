class_name GDSQLResultMaterializationTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const TestResource = preload("res://tests/fixtures/gdsql_test_resource.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_result_materialization_%d" % _test_index)


func test_dictionary_materializer_maps_selected_columns() -> void:
	var query_result := _select_heroes()
	var mapping := GDSQLResultMapping.new() \
			.map_column(&"id", &"hero_id") \
			.map_column(&"name", &"display_name")

	var result := query_result.materialize(
		GDSQLDictionaryResultMaterializer.new(),
		mapping,
	)
	var dictionaries: Array = result.get_value()

	assert_bool(result.is_successful()).is_true()
	assert_int(dictionaries.size()).is_equal(2)
	assert_int(dictionaries[0][&"hero_id"]).is_equal(1)
	assert_str(dictionaries[0][&"display_name"]).is_equal("Knight")
	assert_bool(dictionaries[0].has(&"level")).is_false()
	assert_int(result.get_returned_rows()).is_equal(2)


func test_resource_materializer_creates_one_resource_per_row() -> void:
	var query_result := _select_heroes()
	var mapping := GDSQLResultMapping.for_resource(TestResource) \
			.map_column(&"id", &"id") \
			.map_column(&"name", &"label") \
			.map_column(&"level", &"level")

	var result := query_result.materialize(
		GDSQLResourceResultMaterializer.new(),
		mapping,
	)
	var resources: Array = result.get_value()

	assert_bool(result.is_successful()).is_true()
	assert_int(resources.size()).is_equal(2)
	assert_object(resources[0]).is_instanceof(TestResource)
	assert_int(resources[0].id).is_equal(1)
	assert_str(resources[0].label).is_equal("Knight")
	assert_int(resources[1].level).is_equal(5)


func _select_heroes() -> GDSQLQueryResult:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{&"id": 1, &"name": "Knight", &"level": 3},
			{&"id": 2, &"name": "Mage", &"level": 5},
		],
	)
	return database.execute(
		database.table(&"heroes").select().order_by_column(&"id").build(),
	)
