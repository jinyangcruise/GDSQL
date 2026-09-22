class_name GDSQLEditorContentReferenceStoreTest
extends GdUnitTestSuite

func test_round_trips_a_cross_role_picker_binding() -> void:
	var settings_path := create_temp_dir("gdsql_content_reference") \
			.path_join("settings.cfg")
	var store := GDSQLEditorContentReferenceStore.new(settings_path)
	var reference := GDSQLEditorContentReference.new(
		&"hero_content",
		&"save_1",
		&"save",
		&"heroes",
		&"hero_content_id",
		&"base_content",
		&"content",
		&"heroes",
		&"id",
		&"HeroContent",
	)

	assert_int(store.save(reference)).is_equal(OK)
	var loaded := store.load_for_table(&"save_1", &"save", &"heroes")

	assert_int(loaded.size()).is_equal(1)
	assert_str(String(loaded[0].relationship_name)).is_equal("hero_content")
	assert_str(String(loaded[0].source_column_name)).is_equal("hero_content_id")
	assert_str(String(loaded[0].target_registration_name)).is_equal("base_content")
	assert_str(String(loaded[0].target_database_name)).is_equal("content")
	assert_str(String(loaded[0].target_table_name)).is_equal("heroes")
	assert_str(String(loaded[0].target_column_name)).is_equal("id")
	assert_str(String(loaded[0].target_model_class)).is_equal("HeroContent")

	assert_int(store.remove(loaded[0])).is_equal(OK)
	assert_array(
		store.load_for_table(&"save_1", &"save", &"heroes"),
	).is_empty()


func test_remove_preserves_other_table_references() -> void:
	var settings_path := create_temp_dir("gdsql_content_reference_remove") \
			.path_join("settings.cfg")
	var store := GDSQLEditorContentReferenceStore.new(settings_path)
	var mistaken := GDSQLEditorContentReference.new(
		&"hero_content",
		&"save_1",
		&"save_1",
		&"Heroes",
		&"id",
		&"data",
		&"content",
		&"hero_thing",
		&"hero_id",
		&"HeroThingContent",
	)
	var intended := GDSQLEditorContentReference.new(
		&"hero_content",
		&"save_1",
		&"save_1",
		&"Heroes",
		&"hero_content_id",
		&"data",
		&"content",
		&"heroes",
		&"id",
		&"HeroContent",
	)
	assert_int(store.save(mistaken)).is_equal(OK)
	assert_int(store.save(intended)).is_equal(OK)

	assert_int(store.remove(mistaken)).is_equal(OK)
	var remaining := store.load_for_table(&"save_1", &"save_1", &"Heroes")

	assert_int(remaining.size()).is_equal(1)
	assert_str(String(remaining[0].source_column_name)).is_equal("hero_content_id")
	assert_str(String(remaining[0].target_table_name)).is_equal("heroes")
