class_name GDSQLContentCacheTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _test_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_content_cache_%d" % _test_index)


func test_cache_hits_until_package_content_changes() -> void:
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_items_table(),
		&"game_content",
	)
	TestDatabase.insert_rows(
		source_database,
		[{ &"id": "iron_sword", &"damage": 12 }],
		&"items",
	)
	var cache_root := _test_root.path_join("cache/effective_content")
	var manager := _manager(cache_root)

	var first := manager.ensure_cache([source])
	var second := manager.ensure_cache([source])
	TestDatabase.insert_rows(
		source_database,
		[{ &"id": "crystal_sword", &"damage": 25 }],
		&"items",
	)
	var changed := manager.ensure_cache([source])
	var opened := GDSQLDatabase.open(&"effective_content", cache_root)
	var selected := opened.get_database().execute(
		opened.get_database().query().select().from_table(&"items").build(),
	)

	assert_bool(first.is_successful()).is_true()
	assert_bool(first.was_rebuilt()).is_true()
	assert_int(second.status).is_equal(GDSQLContentCacheResult.Status.HIT)
	assert_bool(changed.was_rebuilt()).is_true()
	assert_bool(opened.is_successful()).is_true()
	assert_int(selected.get_returned_rows()).is_equal(2)
	assert_bool(
		first.manifest.packages[0].content_hash \
				!= changed.manifest.packages[0].content_hash,
	).is_true()


func test_invalid_manifest_is_a_recoverable_cache_miss() -> void:
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_items_table(),
		&"game_content",
	)
	TestDatabase.insert_rows(
		source_database,
		[{ &"id": "iron_sword", &"damage": 12 }],
		&"items",
	)
	var cache_root := _test_root.path_join("cache/effective_content")
	var manager := _manager(cache_root)
	assert_bool(manager.ensure_cache([source]).is_successful()).is_true()
	var invalid := ConfigFile.new()
	invalid.set_value("broken", "value", true)
	assert_int(invalid.save(cache_root.path_join("manifest.cfg"))).is_equal(OK)

	var recovered := manager.ensure_cache([source])

	assert_bool(recovered.is_successful()).is_true()
	assert_bool(recovered.was_rebuilt()).is_true()
	assert_array(_diagnostic_codes(recovered)).contains(
		["GDSQL_CONTENT_CACHE_MANIFEST_INVALID"],
	)


func test_activation_replaces_content_only_after_the_cache_opens() -> void:
	var base := GDSQLDatabase.create(&"base_content", _test_root.path_join("base_active")) \
			.get_database()
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_items_table(),
		&"game_content",
	)
	TestDatabase.insert_rows(
		source_database,
		[{ &"id": "iron_sword", &"damage": 12 }],
		&"items",
	)
	var registry := GDSQLDatabaseRegistry.new()
	registry.register(&"base_content", base)
	registry.bind_role(GDSQLDatabaseRegistry.CONTENT_ROLE, &"base_content")
	var runtime := GDSQLRuntimeSession.new(
		registry,
		GDSQLModelContext.new(GDSQLModelRegistry.new(registry)),
		GDSQLPersistenceCoordinator.new(),
	)

	var activated := GDSQLRuntimeFactory.activate_effective_content(
		runtime,
		_manager(_test_root.path_join("cache/activated")),
		[source],
	)
	var selected := runtime.database(GDSQLDatabaseRegistry.CONTENT_ROLE).get_database()
	var rows := selected.execute(selected.table(&"items").select().build())

	assert_bool(activated.is_successful()).is_true()
	assert_bool(activated.was_rebuilt()).is_true()
	assert_str(String(registry.get_role_registration(&"content"))).is_equal(
		"effective_content",
	)
	assert_object(selected).is_same(activated.get_database())
	assert_int(rows.get_returned_rows()).is_equal(1)


func test_failed_content_preparation_preserves_the_active_role() -> void:
	var base := GDSQLDatabase.create(&"base_content", _test_root.path_join("base_failure")) \
			.get_database()
	var registry := GDSQLDatabaseRegistry.new()
	registry.register(&"base_content", base)
	registry.bind_role(GDSQLDatabaseRegistry.CONTENT_ROLE, &"base_content")
	var runtime := GDSQLRuntimeSession.new(
		registry,
		GDSQLModelContext.new(GDSQLModelRegistry.new(registry)),
		GDSQLPersistenceCoordinator.new(),
	)
	var missing := GDSQLContentPackageSource.new(
		_test_root.path_join("missing_package"),
		GDSQLContentPackageManifest.new(
			&"missing.package",
			"Missing Package",
			"1.0.0",
			GDSQLContentPackageKind.Kind.BASE_GAME,
		),
	)

	var activated := GDSQLRuntimeFactory.activate_effective_content(
		runtime,
		_manager(_test_root.path_join("cache/failure")),
		[missing],
	)

	assert_bool(activated.is_successful()).is_false()
	assert_str(String(registry.get_role_registration(&"content"))).is_equal(
		"base_content",
	)
	assert_object(runtime.database(&"content").get_database()).is_same(base)
	assert_bool(registry.is_registered(&"effective_content")).is_false()


func _manager(cache_root: String) -> GDSQLContentCacheManager:
	return GDSQLContentCacheManager.new(
		GDSQLContentOverlayLoader.new(
			GDSQLConfigFileContentPackageLayerReader.new(),
		),
		GDSQLConfigFileContentPackageFingerprintProvider.new(),
		GDSQLConfigFileContentCacheStore.new(cache_root),
	)


func _source() -> GDSQLContentPackageSource:
	return GDSQLContentPackageSource.new(
		_test_root.path_join("base.game"),
		GDSQLContentPackageManifest.new(
			&"base.game",
			"Base Game",
			"1.0.0",
			GDSQLContentPackageKind.Kind.BASE_GAME,
		),
	)


func _items_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"items", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"damage", TYPE_INT, false))
	return table


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
