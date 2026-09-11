class_name GDSQLRuntimeNodeTest
extends GdUnitTestSuite

const RUNTIME_NODE_SCENE := preload(
	"res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
)

var _test_root: String
var _registry_path: String
var _save_root: String
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_test_root = create_temp_dir("gdsql_runtime_node_%d" % _test_index)
	_registry_path = _test_root.path_join("registry.cfg")
	_save_root = _test_root.path_join("save")
	_create_save_database()
	_save_registry_snapshot()


func after_test() -> void:
	GDSQLModels.clear_context()


func test_scene_bootstraps_the_runtime_with_periodic_policy() -> void:
	var runtime_node := _create_runtime_node()

	var started := runtime_node.start()
	var policy := runtime_node.get_runtime() \
			.get_persistence_coordinator() \
			.get_policy(&"save_1")

	assert_bool(started.is_successful()).is_true()
	assert_object(runtime_node.get_runtime()).is_not_null()
	assert_object(runtime_node.get_start_result()).is_same(started)
	assert_bool(runtime_node.is_started()).is_true()
	assert_bool(runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).is_successful()).is_true()
	assert_int(policy.mode).is_equal(GDSQLCheckpointPolicy.Mode.PERIODIC)
	assert_float(policy.interval_seconds).is_equal(30.0)
	assert_float(
		(runtime_node.get_node("%CheckpointTimer") as Timer).time_left,
	).is_greater(0.0)
	runtime_node.stop(false)


func test_timer_checkpoint_transfers_committed_rows_to_durable_storage() -> void:
	var runtime_node := _create_runtime_node()
	assert_bool(runtime_node.start().is_successful()).is_true()
	var save := runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	assert_bool(
		save.execute(
			save.table(&"heroes") \
					.update() \
					.set_value(&"name", "Paladin") \
					.where(GDSQLExpr.column(&"id").equals(1)) \
					.build(),
		).is_successful(),
	).is_true()

	(runtime_node.get_node("%CheckpointTimer") as Timer).timeout.emit()
	var durable := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var selected := durable.execute(durable.table(&"heroes").select().build())

	assert_str(selected.rows[0].get_value(&"name")).is_equal("Paladin")
	runtime_node.stop(false)


func test_stop_checkpoints_and_releases_the_runtime_context() -> void:
	var runtime_node := _create_runtime_node()
	assert_bool(runtime_node.start().is_successful()).is_true()
	var save := runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	assert_bool(
		save.execute(
			save.table(&"heroes") \
					.update() \
					.set_value(&"name", "Ranger") \
					.where(GDSQLExpr.column(&"id").equals(1)) \
					.build(),
		).is_successful(),
	).is_true()

	var stopped := runtime_node.stop()
	var durable := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var selected := durable.execute(durable.table(&"heroes").select().build())

	assert_bool(stopped.is_successful()).is_true()
	assert_array(stopped.checkpointed_databases).contains_exactly([&"save_1"])
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Ranger")
	assert_object(runtime_node.get_runtime()).is_null()
	assert_bool(runtime_node.is_started()).is_false()
	assert_object(GDSQLModels.get_context()).is_null()


func test_operations_before_start_return_structured_diagnostics() -> void:
	var runtime_node := auto_free(GDSQLRuntimeNode.new()) as GDSQLRuntimeNode

	var database := runtime_node.database(GDSQLDatabaseRegistry.CONTENT_ROLE)
	var checkpoint := runtime_node.checkpoint_now()

	assert_bool(database.is_successful()).is_false()
	assert_str(String(database.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RUNTIME_NOT_STARTED",
	)
	assert_bool(checkpoint.is_successful()).is_false()
	assert_str(String(checkpoint.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RUNTIME_NOT_STARTED",
	)


func _create_runtime_node() -> GDSQLRuntimeNode:
	var runtime_node := auto_free(RUNTIME_NODE_SCENE.instantiate()) \
			as GDSQLRuntimeNode
	runtime_node.auto_start = false
	runtime_node.registry_path = _registry_path
	add_child(runtime_node)
	return runtime_node


func _create_save_database() -> void:
	var database := GDSQLDatabase.create(&"save_1", _save_root).get_database()
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(heroes).is_successful()).is_true()
	assert_bool(
		database.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful(),
	).is_true()


func _save_registry_snapshot() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"save_1",
			_save_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
	)
	assert_bool(
		GDSQLConfigFileDatabaseRegistryStore.new(_registry_path) \
				.save_snapshot(snapshot) \
				.is_successful(),
	).is_true()
