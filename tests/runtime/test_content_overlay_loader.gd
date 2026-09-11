class_name GDSQLContentOverlayLoaderTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _test_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_content_overlay_%d" % _test_index)


func test_ordered_layers_add_override_and_remove_without_mutating_sources() -> void:
	var base := _source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME)
	var mod := _source(&"arsenal", GDSQLContentPackageKind.Kind.MOD)
	var base_database := _create_package_database(
		base,
		_items_table(TYPE_INT),
		[
			{ &"id": "iron_sword", &"damage": 12 },
			{ &"id": "wooden_sword", &"damage": 3 },
		],
	)
	_create_package_database(
		mod,
		_items_table(TYPE_INT),
		[
			{ &"id": "iron_sword", &"damage": 18 },
			{ &"id": "crystal_sword", &"damage": 25 },
		],
	)
	_write_removals(mod, &"items", ["wooden_sword"])

	var built := GDSQLContentOverlayLoader.new(
		GDSQLConfigFileContentPackageLayerReader.new(),
	).build_effective_database([base, mod])
	var snapshot := built.database
	var items := snapshot.get_table(&"items")

	assert_bool(built.is_successful()).is_true()
	assert_str(String(snapshot.definition.name)).is_equal("effective_content")
	assert_str(String(snapshot.get_table_definition(&"items").database_name)).is_equal(
		"effective_content",
	)
	assert_array(_row_ids(items.rows)).contains_exactly(
		["crystal_sword", "iron_sword"],
	)
	assert_int(items.find_by_primary_key("iron_sword").get_value(&"damage")).is_equal(18)
	assert_object(items.find_by_primary_key("wooden_sword")).is_null()
	assert_int(
		base_database
		.execute(base_database.query().select().from_table(&"items").build())
		.rows[0]
		.get_value(&"damage"),
	).is_equal(12)


func test_incompatible_schema_stops_overlay_construction() -> void:
	var base := _source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME)
	var mod := _source(&"balance", GDSQLContentPackageKind.Kind.MOD)
	_create_package_database(
		base,
		_items_table(TYPE_INT),
		[{ &"id": "iron_sword", &"damage": 12 }],
	)
	_create_package_database(
		mod,
		_items_table(TYPE_FLOAT),
		[{ &"id": "iron_sword", &"damage": 18.0 }],
	)

	var built := GDSQLContentOverlayLoader.new(
		GDSQLConfigFileContentPackageLayerReader.new(),
	).build_effective_database([base, mod])

	assert_bool(built.is_successful()).is_false()
	assert_object(built.database).is_null()
	assert_array(_diagnostic_codes(built)).contains(["GDSQL_CONTENT_SCHEMA_CONFLICT"])


func test_removal_only_package_can_target_a_base_table() -> void:
	var base := _source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME)
	var mod := _source(&"cleanup", GDSQLContentPackageKind.Kind.MOD)
	_create_package_database(
		base,
		_items_table(TYPE_INT),
		[{ &"id": "deprecated", &"damage": 1 }],
	)
	_write_removals(mod, &"items", ["deprecated"])

	var built := GDSQLContentOverlayLoader.new(
		GDSQLConfigFileContentPackageLayerReader.new(),
	).build_effective_database([base, mod])

	assert_bool(built.is_successful()).is_true()
	assert_int(built.database.get_table(&"items").rows.size()).is_equal(0)


func _source(
		package_id: StringName,
		kind: int,
) -> GDSQLContentPackageSource:
	return GDSQLContentPackageSource.new(
		_test_root.path_join(String(package_id)),
		GDSQLContentPackageManifest.new(
			package_id,
			String(package_id),
			"1.0.0",
			kind,
		),
	)


func _create_package_database(
		source: GDSQLContentPackageSource,
		table: GDSQLTableDefinition,
		rows: Array[Dictionary],
) -> GDSQLDatabase:
	var database := TestDatabase.create_database(
		source.get_data_root(),
		table,
		&"game_content",
	)
	TestDatabase.insert_rows(database, rows, table.name)
	return database


func _items_table(damage_type: Variant.Type) -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"items", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"damage", damage_type, false))
	return table


func _write_removals(
		source: GDSQLContentPackageSource,
		table_name: StringName,
		identities: Array,
) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(source.package_root)).is_equal(OK)
	var config := ConfigFile.new()
	config.set_value(
		"remove:game_content:%s" % table_name,
		"ids",
		identities,
	)
	assert_int(
		config.save(source.package_root.path_join("overlays.cfg")),
	).is_equal(OK)


func _row_ids(rows: Array[GDSQLRowRecord]) -> Array[String]:
	var ids: Array[String] = []
	for row in rows:
		ids.append(row.get_value(&"id"))
	return ids


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
