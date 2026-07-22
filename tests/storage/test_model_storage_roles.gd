class_name GDSQLModelStorageRolesTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _test_index := 0
var _content_root: String
var _save_root: String
var _settings_root: String
var _content_database: GDSQLDatabase
var _save_database: GDSQLDatabase
var _settings_database: GDSQLDatabase
var _database_registry: GDSQLDatabaseRegistry


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_content_root = create_temp_dir("gdsql_model_content_%d" % _test_index)
	_save_root = create_temp_dir("gdsql_model_save_%d" % _test_index)
	_settings_root = create_temp_dir("gdsql_model_settings_%d" % _test_index)
	_content_database = _create_memory_database(
		_content_root,
		&"content",
		_content_table(),
		[
			GDSQLRowRecord.new({ &"id": 1, &"name": "Knight" }),
		],
	)
	_save_database = _create_memory_database(
		_save_root,
		&"save_slot",
		_save_table(),
		[
			GDSQLRowRecord.new({ &"id": 1, &"hero_id": 1, &"level": 3 }),
		],
	)
	_settings_database = _create_memory_database(
		_settings_root,
		&"settings",
		_settings_table(),
		[
			GDSQLRowRecord.new({ &"id": 1, &"volume": 80 }),
		],
	)
	_database_registry = GDSQLDatabaseRegistry.new()
	_register_database(&"content", GDSQLDatabaseRegistry.CONTENT_ROLE, _content_database)
	_register_database(&"save", GDSQLDatabaseRegistry.SAVE_ROLE, _save_database)
	_register_database(&"settings", GDSQLDatabaseRegistry.SETTINGS_ROLE, _settings_database)
	var model_registry := GDSQLModelRegistry.new(_database_registry)
	assert_bool(model_registry.register(ContentHero).is_successful()).is_true()
	assert_bool(model_registry.register(SaveState).is_successful()).is_true()
	assert_bool(model_registry.register(GameSetting).is_successful()).is_true()
	assert_bool(
		GDSQLModels.configure(GDSQLModelContext.new(model_registry)).is_successful(),
	).is_true()


func after_test() -> void:
	GDSQLModels.clear_context()


func test_content_model_reads_from_content_storage_without_dirtying_it() -> void:
	var result := ContentHero.find(1)
	var hero := result.get_value() as ContentHero

	assert_bool(result.is_successful()).is_true()
	assert_str(hero.name).is_equal("Knight")
	assert_bool(_memory(_content_database).is_dirty()).is_false()


func test_content_model_remains_read_only_on_in_memory_storage() -> void:
	var hero := ContentHero.find(1).get_value() as ContentHero
	hero.name = "Paladin"

	var result := hero.save()

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_READ_ONLY",
	)
	assert_bool(_memory(_content_database).is_dirty()).is_false()


func test_save_model_mutation_marks_only_the_save_storage_dirty() -> void:
	var state := SaveState.find(1).get_value() as SaveState
	state.level = 4

	var result := state.save()

	assert_bool(result.is_successful()).is_true()
	assert_int(state.level).is_equal(4)
	assert_bool(_memory(_save_database).is_dirty()).is_true()
	assert_bool(_memory(_content_database).is_dirty()).is_false()
	assert_bool(_memory(_settings_database).is_dirty()).is_false()


func test_settings_model_mutation_is_independent_from_the_save_slot() -> void:
	var setting := GameSetting.find(1).get_value() as GameSetting
	setting.volume = 60

	var result := setting.save()

	assert_bool(result.is_successful()).is_true()
	assert_int(setting.volume).is_equal(60)
	assert_bool(_memory(_settings_database).is_dirty()).is_true()
	assert_bool(_memory(_save_database).is_dirty()).is_false()


func test_rebinding_save_role_changes_the_database_used_by_save_models() -> void:
	var second_root := create_temp_dir("gdsql_model_save_second_%d" % _test_index)
	var second_save := _create_memory_database(
		second_root,
		&"save_slot_2",
		_save_table(),
		[
			GDSQLRowRecord.new({ &"id": 1, &"hero_id": 2, &"level": 9 }),
		],
	)
	assert_bool(_database_registry.register(&"save_2", second_save).is_successful()).is_true()
	assert_bool(
		_database_registry.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_2")
		.is_successful(),
	).is_true()

	var state := SaveState.find(1).get_value() as SaveState

	assert_int(state.hero_id).is_equal(2)
	assert_int(state.level).is_equal(9)


func test_save_model_checkpoint_persists_changes_and_clears_dirty_state() -> void:
	var state := SaveState.find(1).get_value() as SaveState
	state.level = 7
	assert_bool(state.save().is_successful()).is_true()
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(
		&"save",
		_checkpoint_target(_save_database, _save_root),
		GDSQLCheckpointPolicy.manual(),
	)

	var checkpoint := coordinator.checkpoint(&"save")
	var persisted := _select_disk_row(_save_root, &"save_slot", &"save_state")

	assert_bool(checkpoint.is_successful()).is_true()
	assert_bool(_memory(_save_database).is_dirty()).is_false()
	assert_int(persisted.get_value(&"level")).is_equal(7)


func test_settings_model_checkpoint_does_not_checkpoint_dirty_save_storage() -> void:
	var state := SaveState.find(1).get_value() as SaveState
	state.level = 5
	assert_bool(state.save().is_successful()).is_true()
	var setting := GameSetting.find(1).get_value() as GameSetting
	setting.volume = 40
	assert_bool(setting.save().is_successful()).is_true()
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(
		&"settings",
		_checkpoint_target(_settings_database, _settings_root),
		GDSQLCheckpointPolicy.manual(),
	)

	var checkpoint := coordinator.checkpoint(&"settings")
	var persisted := _select_disk_row(_settings_root, &"settings", &"game_settings")

	assert_bool(checkpoint.is_successful()).is_true()
	assert_int(persisted.get_value(&"volume")).is_equal(40)
	assert_bool(_memory(_settings_database).is_dirty()).is_false()
	assert_bool(_memory(_save_database).is_dirty()).is_true()


func _create_memory_database(
		data_root: String,
		database_name: StringName,
		table: GDSQLTableDefinition,
		rows: Array[GDSQLRowRecord],
) -> GDSQLDatabase:
	TestDatabase.create_database(data_root, table, database_name)
	var context := GDSQLRuntimeFactory.create_in_memory(data_root)
	var database := GDSQLDatabase.new(database_name, context)
	var catalog_table := context.catalog.get_table(database_name, table.name)
	assert_bool(
		(context.storage as GDSQLInMemoryTableStorage)
		.load_table(catalog_table, rows)
		.is_successful(),
	).is_true()
	return database


func _register_database(
		registration_name: StringName,
		role: StringName,
		database: GDSQLDatabase,
) -> void:
	assert_bool(
		_database_registry.register(registration_name, database).is_successful(),
	).is_true()
	assert_bool(
		_database_registry.bind_role(role, registration_name).is_successful(),
	).is_true()


func _memory(database: GDSQLDatabase) -> GDSQLInMemoryTableStorage:
	return database.context.storage as GDSQLInMemoryTableStorage


func _checkpoint_target(
		database: GDSQLDatabase,
		data_root: String,
) -> GDSQLInMemoryCheckpointTarget:
	return GDSQLInMemoryCheckpointTarget.new(
		_memory(database),
		GDSQLConfigFileTableStorage.new(
			GDSQLDatabasePathResolver.new(data_root),
			GDSQLConfigFileCache.new(),
			GDSQLGodotVariantCodec.new(),
		),
	)


func _select_disk_row(
		data_root: String,
		database_name: StringName,
		table_name: StringName,
) -> GDSQLRowRecord:
	var database := GDSQLDatabase.open(database_name, data_root).get_database()
	var result := database.execute(database.table(table_name).select().build())
	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	return result.rows[0]


func _content_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	return table


func _save_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"save_state", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"level", TYPE_INT, false))
	return table


func _settings_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"game_settings", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"volume", TYPE_INT, false))
	return table


class ContentHero extends GDSQLContentModel:
	var id: int
	var name: String


	static func find(identity: int) -> GDSQLQueryResult:
		return GDSQLModels.find(ContentHero, identity)


	func table_name() -> StringName:
		return &"heroes"


class SaveState extends GDSQLSaveModel:
	var id: int
	var hero_id: int
	var level: int


	static func find(identity: int) -> GDSQLQueryResult:
		return GDSQLModels.find(SaveState, identity)


	func table_name() -> StringName:
		return &"save_state"


class GameSetting extends GDSQLSettingsModel:
	var id: int
	var volume: int


	static func find(identity: int) -> GDSQLQueryResult:
		return GDSQLModels.find(GameSetting, identity)


	func table_name() -> StringName:
		return &"game_settings"
