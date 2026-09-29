class_name GDSQLManagedContentConfigurationStoreTest
extends GdUnitTestSuite

var _settings_path: String


func before_test() -> void:
	_settings_path = create_temp_dir("gdsql_managed_configuration").path_join("settings.cfg")


func test_defaults_match_the_managed_editor_profile() -> void:
	var loaded := GDSQLConfigFileManagedContentConfigurationStore.new(
		_settings_path,
	).load_configuration()
	var configuration := loaded.get_value() as GDSQLManagedContentConfiguration

	assert_bool(loaded.is_successful()).is_true()
	assert_str(configuration.base_package_root).is_equal("res://content/base")
	assert_array(configuration.package_container_roots).contains_exactly(
		["res://content/packages", "user://gdsql/mods"],
	)
	assert_array(configuration.enabled_package_ids).is_empty()


func test_round_trip_preserves_the_selected_setup_profile() -> void:
	var profile_store := GDSQLConfigFileSetupProfileStore.new(_settings_path)
	assert_bool(profile_store.save_profile(GDSQLSetupProfile.Kind.MANAGED).is_successful()).is_true()
	var store := GDSQLConfigFileManagedContentConfigurationStore.new(_settings_path)
	var expected := GDSQLManagedContentConfiguration.new(
		"res://packs/base",
		["res://packs/optional", "user://packs"],
		[&"expansion", &"balance"],
	)

	var saved := store.save_configuration(expected)
	var loaded := store.load_configuration()
	var restored := loaded.get_value() as GDSQLManagedContentConfiguration
	var profile := profile_store.load_profile()

	assert_bool(saved.is_successful()).is_true()
	assert_bool(loaded.is_successful()).is_true()
	assert_str(restored.base_package_root).is_equal("res://packs/base")
	assert_array(restored.package_container_roots).contains_exactly(
		["res://packs/optional", "user://packs"],
	)
	assert_array(restored.enabled_package_ids).contains_exactly([&"expansion", &"balance"])
	assert_int(profile.get_value()).is_equal(GDSQLSetupProfile.Kind.MANAGED)
