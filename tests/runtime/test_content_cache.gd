class_name GDSQLContentCacheTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"

var _test_root: String
var _test_index := 0


class CountingResolver:
	extends GDSQLResourceResolver

	var calls := 0
	var resolved_resource: Resource


	func _init(resource: Resource) -> void:
		resolved_resource = resource


	func resolve(_reference: GDSQLResourceReference) -> GDSQLOperationResult:
		calls += 1
		var result := GDSQLOperationResult.new()
		result.value = resolved_resource
		return result


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_content_cache_%d" % _test_index)


func test_cache_hits_until_package_content_changes() -> void:
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_items_table(),
		&"content",
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


func test_cache_persists_foreign_keys_after_all_referenced_tables_exist() -> void:
	var source := _source()
	var heroes := GDSQLTableDefinition.new(&"z_heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING, false, true))
	var skills := GDSQLTableDefinition.new(&"a_skills", &"id")
	skills.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING, false, true))
	skills.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_STRING, false))
	skills.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"skills_hero",
			&"hero_id",
			&"z_heroes",
			&"id",
		),
	)
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		heroes,
		&"content",
	)
	assert_bool(source_database.create_table(skills).is_successful()).is_true()
	TestDatabase.insert_rows(source_database, [{&"id": "hero.mage"}], &"z_heroes")
	TestDatabase.insert_rows(
		source_database,
		[{&"id": "skill.fireball", &"hero_id": "hero.mage"}],
		&"a_skills",
	)
	var cache_root := _test_root.path_join("cache/effective_content")

	var cached := _manager(cache_root).ensure_cache([source])
	var opened := GDSQLDatabase.open(&"effective_content", cache_root)

	assert_bool(cached.is_successful()).is_true()
	assert_bool(opened.is_successful()).is_true()
	var stored := opened.get_database().context.catalog.get_table(
		&"effective_content",
		&"a_skills",
	)

	assert_object(stored.get_foreign_key(&"skills_hero")).is_not_null()


func test_cache_rebuild_copies_resource_identity_without_loading_the_asset() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_resource_items_table(icon),
		&"content",
	)
	TestDatabase.insert_rows(
		source_database,
		[{&"id": "key", &"damage": 0, &"name": "Key", &"icon": icon}],
		&"items",
	)
	var resolver := CountingResolver.new(icon)
	var cache_root := _test_root.path_join("cache/resource_identity")
	var cached := _manager(
		cache_root,
		GDSQLGodotVariantCodec.new(resolver),
	).ensure_cache([source])

	assert_bool(cached.is_successful()).is_true()
	assert_int(resolver.calls).is_zero()
	var table_text := FileAccess.get_file_as_string(
		cache_root.path_join("effective_content/tables/items.cfg"),
	)
	assert_bool(table_text.contains("resource_reference")).is_true()
	assert_bool(table_text.contains(REFERENCED_ICON_PATH)).is_true()

	var opened := GDSQLDatabase.open(&"effective_content", cache_root)
	assert_bool(opened.is_successful()).is_true()
	var database := opened.get_database()
	database.context.executor = GDSQLDefaultQueryExecutor.new(resolver)
	var names := database.execute(
		database.table(&"items").select().column(&"name").build(),
	)
	assert_bool(names.is_successful()).is_true()
	assert_int(resolver.calls).is_zero()
	var icons := database.execute(
		database.table(&"items").select().column(&"icon").build(),
	)
	assert_bool(icons.is_successful()).is_true()
	assert_object(icons.rows[0].get_value(&"icon")).is_same(icon)
	assert_int(resolver.calls).is_equal(1)


func test_invalid_manifest_is_a_recoverable_cache_miss() -> void:
	var source := _source()
	var source_database := TestDatabase.create_database(
		source.get_data_root(),
		_items_table(),
		&"content",
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
		&"content",
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


func _manager(
		cache_root: String,
		codec: GDSQLGodotVariantCodec = null,
) -> GDSQLContentCacheManager:
	return GDSQLContentCacheManager.new(
		GDSQLContentOverlayLoader.new(
			GDSQLConfigFileContentPackageLayerReader.new(codec),
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


func _resource_items_table(icon: Resource) -> GDSQLTableDefinition:
	var table := _items_table()
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var icon_column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	icon_column.resource_type = GDSQLResourceTypeConstraint.from_resource(icon)
	icon_column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	table.add_column(icon_column)
	return table


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
