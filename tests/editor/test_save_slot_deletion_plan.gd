class_name GDSQLSaveSlotDeletionPlanTest
extends GdUnitTestSuite

func test_builds_an_exact_standard_save_slot_target() -> void:
	var registration := GDSQLDatabaseRegistration.new(
		&"save_1",
		&"game_state",
		"user://gdsql/saves/save_1/",
	)

	var result := GDSQLSaveSlotDeletionPlan.build(registration, &"save_1")
	var plan := result.get_value() as GDSQLSaveSlotDeletionPlan

	assert_bool(result.is_successful()).is_true()
	assert_str(String(plan.registration_name)).is_equal("save_1")
	assert_str(String(plan.database_name)).is_equal("game_state")
	assert_str(plan.data_root).is_equal("user://gdsql/saves/save_1")
	assert_str(plan.database_path).is_equal(
		"user://gdsql/saves/save_1/game_state",
	)
	assert_bool(plan.was_active).is_true()
	assert_str(String(plan.fallback_registration_name)).is_empty()


func test_active_slot_selects_the_first_compatible_fallback() -> void:
	var removed := GDSQLDatabaseRegistration.new(
		&"save_2",
		&"game_state",
		"user://gdsql/saves/save_2",
		GDSQLStorageBackendIds.IN_MEMORY,
		&"game_state",
	)
	var save_1 := GDSQLDatabaseRegistration.new(
		&"save_1",
		&"game_state",
		"user://gdsql/saves/save_1",
		GDSQLStorageBackendIds.IN_MEMORY,
		&"game_state",
	)
	var save_3 := GDSQLDatabaseRegistration.new(
		&"save_3",
		&"game_state",
		"user://gdsql/saves/save_3",
		GDSQLStorageBackendIds.IN_MEMORY,
		&"game_state",
	)
	var incompatible := GDSQLDatabaseRegistration.new(
		&"legacy",
		&"legacy_state",
		"user://gdsql/saves/legacy",
	)

	var result := GDSQLSaveSlotDeletionPlan.build(
		removed,
		&"save_2",
		[save_3, incompatible, save_1, removed],
	)
	var plan := result.get_value() as GDSQLSaveSlotDeletionPlan

	assert_bool(result.is_successful()).is_true()
	assert_str(String(plan.fallback_registration_name)).is_equal("save_1")


func test_non_active_slot_does_not_request_a_fallback() -> void:
	var removed := GDSQLDatabaseRegistration.new(
		&"save_2",
		&"game_state",
		"user://gdsql/saves/save_2",
	)
	var save_1 := GDSQLDatabaseRegistration.new(
		&"save_1",
		&"game_state",
		"user://gdsql/saves/save_1",
	)

	var plan := GDSQLSaveSlotDeletionPlan.build(
		removed,
		&"save_1",
		[save_1, removed],
	).get_value() as GDSQLSaveSlotDeletionPlan

	assert_bool(plan.was_active).is_false()
	assert_str(String(plan.fallback_registration_name)).is_empty()


func test_rejects_the_shared_save_root() -> void:
	var result := GDSQLSaveSlotDeletionPlan.build(
		GDSQLDatabaseRegistration.new(
			&"all_saves",
			&"game_state",
			"user://gdsql/saves",
		),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_SAVE_SLOT_DELETE_ROOT_REJECTED",
	)


func test_rejects_custom_and_nested_roots() -> void:
	for root in [
		"res://data",
		"user://gdsql/settings",
		"user://gdsql/saves/save_1/nested",
		"user://gdsql/saves/save_1/../..",
	]:
		var result := GDSQLSaveSlotDeletionPlan.build(
			GDSQLDatabaseRegistration.new(&"save_1", &"game_state", root),
		)
		assert_bool(result.is_successful()).is_false()
