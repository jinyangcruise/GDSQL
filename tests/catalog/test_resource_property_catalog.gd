class_name GDSQLResourcePropertyCatalogTest
extends GdUnitTestSuite

const TestResource = preload("res://tests/fixtures/gdsql_test_resource.gd")


func test_box_mesh_exposes_vector_components_but_not_vector_container() -> void:
	var constraint := GDSQLResourceTypeConstraint.from_resource(BoxMesh.new())
	var definitions := GDSQLResourcePropertyCatalog.new().list_filterable_leaves(constraint)
	var types_by_path: Dictionary = { }
	for definition in definitions:
		types_by_path[definition.serialized_path()] = definition.data_type

	assert_bool(types_by_path.has("size")).is_false()
	assert_int(types_by_path.get("size:x", TYPE_NIL)).is_equal(TYPE_FLOAT)
	assert_int(types_by_path.get("size:y", TYPE_NIL)).is_equal(TYPE_FLOAT)
	assert_int(types_by_path.get("size:z", TYPE_NIL)).is_equal(TYPE_FLOAT)


func test_filterable_leaf_resolution_rejects_unknown_or_compound_paths() -> void:
	var constraint := GDSQLResourceTypeConstraint.from_resource(BoxMesh.new())
	var catalog := GDSQLResourcePropertyCatalog.new()

	assert_object(catalog.resolve_filterable_leaf(constraint, "size")).is_null()
	assert_object(catalog.resolve_filterable_leaf(constraint, "missing:x")).is_null()
	var leaf := catalog.resolve_filterable_leaf(constraint, "size:x")
	assert_object(leaf).is_not_null()
	assert_int(leaf.data_type).is_equal(TYPE_FLOAT)


func test_custom_resource_uses_exported_script_property_metadata() -> void:
	var constraint := GDSQLResourceTypeConstraint.from_resource(TestResource.new())
	var definitions := GDSQLResourcePropertyCatalog.new().list_filterable_leaves(constraint)
	var types_by_path: Dictionary = { }
	for definition in definitions:
		types_by_path[definition.serialized_path()] = definition.data_type

	assert_int(types_by_path.get("id", TYPE_NIL)).is_equal(TYPE_INT)
	assert_int(types_by_path.get("label", TYPE_NIL)).is_equal(TYPE_STRING)
	assert_int(types_by_path.get("level", TYPE_NIL)).is_equal(TYPE_INT)
