class_name GDSQLSetupProfileStoreTest
extends GdUnitTestSuite

var _settings_path: String


func before_test() -> void:
	_settings_path = create_temp_dir("gdsql_setup_profile").path_join("settings.cfg")


func test_profile_store_defaults_to_unselected_and_round_trips_selection() -> void:
	var store := GDSQLConfigFileSetupProfileStore.new(_settings_path)

	var initial := store.load_profile()
	var saved := store.save_profile(GDSQLSetupProfile.Kind.MANAGED)
	var loaded := store.load_profile()

	assert_bool(initial.is_successful()).is_true()
	assert_int(initial.get_value()).is_equal(GDSQLSetupProfile.Kind.UNSELECTED)
	assert_bool(saved.is_successful()).is_true()
	assert_int(loaded.get_value()).is_equal(GDSQLSetupProfile.Kind.MANAGED)


func test_clearing_profile_preserves_unrelated_project_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("models", "root", "res://game_models")
	assert_int(config.save(_settings_path)).is_equal(OK)
	var store := GDSQLConfigFileSetupProfileStore.new(_settings_path)
	assert_bool(store.save_profile(GDSQLSetupProfile.Kind.DIRECT).is_successful()).is_true()

	var cleared := store.clear_profile()
	var stored := ConfigFile.new()
	assert_int(stored.load(_settings_path)).is_equal(OK)

	assert_bool(cleared.is_successful()).is_true()
	assert_int(store.load_profile().get_value()).is_equal(GDSQLSetupProfile.Kind.UNSELECTED)
	assert_str(stored.get_value("models", "root")).is_equal("res://game_models")
	assert_bool(stored.has_section_key("setup", "profile")).is_false()


func test_profile_store_rejects_unknown_persisted_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("setup", "profile", "experimental")
	assert_int(config.save(_settings_path)).is_equal(OK)

	var loaded := GDSQLConfigFileSetupProfileStore.new(_settings_path).load_profile()

	assert_bool(loaded.is_successful()).is_false()
	assert_str(String(loaded.diagnostics.entries[0].code)).is_equal(
		"GDSQL_SETUP_PROFILE_INVALID",
	)
