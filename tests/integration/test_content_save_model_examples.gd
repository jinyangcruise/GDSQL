class_name GDSQLContentSaveModelExamplesTest
extends GdUnitTestSuite

const ContentItem = preload(
	"res://examples/runtime/content_save_models/content_item.gd"
)
const InventoryEntry = preload(
	"res://examples/runtime/content_save_models/inventory_entry.gd"
)
const RuntimeNodeScene = preload(
	"res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
)

var _test_root: String
var _registry_path: String
var _content_root: String
var _save_one_root: String
var _save_two_root: String
var _runtime_node: GDSQLRuntimeNode
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_test_root = create_temp_dir("gdsql_content_save_example_%d" % _test_index)
	_registry_path = _test_root.path_join("registry.cfg")
	_content_root = _test_root.path_join("content")
	_save_one_root = _test_root.path_join("save_1")
	_save_two_root = _test_root.path_join("save_2")
	_create_content_database()
	_create_save_database(&"save_1", _save_one_root, 1)
	_create_save_database(&"save_2", _save_two_root, 3)
	_save_registry_snapshot()
	_runtime_node = auto_free(RuntimeNodeScene.instantiate()) as GDSQLRuntimeNode
	_runtime_node.auto_start = false
	_runtime_node.registry_path = _registry_path
	add_child(_runtime_node)
	assert_bool(_runtime_node.start().is_successful()).is_true()
	assert_bool(_runtime_node.register_model(ContentItem).is_successful()).is_true()
	assert_bool(_runtime_node.register_model(InventoryEntry).is_successful()).is_true()


func after_test() -> void:
	if _runtime_node != null and _runtime_node.is_started():
		_runtime_node.stop(false)
	GDSQLModels.clear_context()


func test_authored_content_lookup_uses_the_content_role() -> void:
	var result := ContentItem.find(&"iron_sword")
	var item := result.get_value() as GDSQLExampleContentItem

	assert_bool(result.is_successful()).is_true()
	assert_object(item).is_not_null()
	assert_str(item.display_name).is_equal("Iron Sword")


func test_save_inventory_resolves_its_content_definition_by_stable_id() -> void:
	var result := InventoryEntry.query().with(&"item").all()
	var entries: Array = result.get_value()
	var item := entries[0].get_related(&"item") as GDSQLExampleContentItem

	assert_bool(result.is_successful()).is_true()
	assert_int(entries.size()).is_equal(1)
	assert_str(String(entries[0].item_id)).is_equal("iron_sword")
	assert_int(entries[0].quantity).is_equal(1)
	assert_object(item).is_not_null()
	assert_str(item.display_name).is_equal("Iron Sword")


func test_save_slot_switch_requires_a_fresh_save_model_query() -> void:
	var old_entry := InventoryEntry.query().first().get_value() \
			as GDSQLExampleInventoryEntry

	var selected := _runtime_node.select_save_slot(&"save_2")
	var fresh_result := InventoryEntry.query().with(&"item").all()
	var fresh_entries: Array = fresh_result.get_value()
	old_entry.quantity = 99
	var stale_save := old_entry.save()

	assert_bool(selected.is_successful()).is_true()
	assert_bool(fresh_result.is_successful()).is_true()
	assert_int(fresh_entries[0].quantity).is_equal(3)
	assert_object(fresh_entries[0].get_related(&"item")).is_not_null()
	assert_bool(stale_save.is_successful()).is_false()
	assert_str(String(stale_save.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_DATABASE_CHANGED",
	)


func _create_content_database() -> void:
	var items := GDSQLTableDefinition.new(&"items", &"id")
	items.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING_NAME, false))
	items.add_column(GDSQLColumnDefinition.new(&"display_name", TYPE_STRING, false))
	var database := GDSQLDatabase.create(&"game_content", _content_root).get_database()
	assert_bool(database.create_table(items).is_successful()).is_true()
	assert_bool(
		database.insert(
			&"items",
			{ &"id": &"iron_sword", &"display_name": "Iron Sword" },
		).is_successful(),
	).is_true()


func _create_save_database(
		database_name: StringName,
		data_root: String,
		quantity: int,
) -> void:
	var inventory := GDSQLTableDefinition.new(&"inventory", &"id")
	inventory.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	inventory.add_column(GDSQLColumnDefinition.new(&"item_id", TYPE_STRING_NAME, false))
	inventory.add_column(GDSQLColumnDefinition.new(&"quantity", TYPE_INT, false))
	var database := GDSQLDatabase.create(database_name, data_root).get_database()
	assert_bool(database.create_table(inventory).is_successful()).is_true()
	assert_bool(
		database.insert(
			&"inventory",
			{ &"id": 1, &"item_id": &"iron_sword", &"quantity": quantity },
		).is_successful(),
	).is_true()


func _save_registry_snapshot() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations = [
		GDSQLDatabaseRegistration.new(
			&"content",
			&"game_content",
			_content_root,
			GDSQLStorageBackendIds.CONFIG_FILE,
		),
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"save_1",
			_save_one_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
		GDSQLDatabaseRegistration.new(
			&"save_2",
			&"save_2",
			_save_two_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	]
	snapshot.role_bindings = [
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.CONTENT_ROLE, &"content"),
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
	]
	assert_bool(
		GDSQLConfigFileDatabaseRegistryStore.new(_registry_path) \
				.save_snapshot(snapshot) \
				.is_successful(),
	).is_true()
