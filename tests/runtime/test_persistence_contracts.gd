class_name GDSQLPersistenceContractsTest
extends GdUnitTestSuite


func test_checkpoint_policy_factories_describe_persistence_timing() -> void:
	assert_int(GDSQLCheckpointPolicy.immediate().mode).is_equal(
		GDSQLCheckpointPolicy.Mode.IMMEDIATE,
	)
	var periodic := GDSQLCheckpointPolicy.periodic(30.0)
	assert_int(periodic.mode).is_equal(GDSQLCheckpointPolicy.Mode.PERIODIC)
	assert_float(periodic.interval_seconds).is_equal(30.0)
	assert_bool(periodic.is_valid()).is_true()
	assert_bool(GDSQLCheckpointPolicy.periodic(0.0).is_valid()).is_false()


func test_manual_checkpoint_persists_only_committed_dirty_state() -> void:
	var target := TestCheckpointTarget.new()
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(&"save_1", target, GDSQLCheckpointPolicy.manual())

	var clean_result := coordinator.checkpoint(&"save_1")
	target.dirty = true
	var dirty_result := coordinator.checkpoint(&"save_1")

	assert_bool(clean_result.is_successful()).is_true()
	assert_int(target.checkpoint_count).is_equal(1)
	assert_bool(dirty_result.is_successful()).is_true()
	assert_array(dirty_result.checkpointed_databases).contains_exactly([&"save_1"])
	assert_bool(target.dirty).is_false()


func test_immediate_policy_checkpoints_after_transaction_commit() -> void:
	var target := TestCheckpointTarget.new()
	target.dirty = true
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(&"settings", target, GDSQLCheckpointPolicy.immediate())

	var result := coordinator.transaction_committed(&"settings")

	assert_bool(result.is_successful()).is_true()
	assert_int(target.checkpoint_count).is_equal(1)
	assert_array(result.checkpointed_databases).contains_exactly([&"settings"])


func test_checkpoint_dirty_retains_failed_databases_for_retry() -> void:
	var successful := TestCheckpointTarget.new()
	successful.dirty = true
	var failing := TestCheckpointTarget.new()
	failing.dirty = true
	failing.checkpoint_succeeds = false
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(&"save_1", successful)
	coordinator.register(&"analytics", failing)

	var result := coordinator.checkpoint_dirty()

	assert_bool(result.is_successful()).is_false()
	assert_array(result.checkpointed_databases).contains_exactly([&"save_1"])
	assert_array(result.dirty_databases).contains_exactly([&"analytics"])


class TestCheckpointTarget extends GDSQLCheckpointTarget:
	var dirty := false
	var checkpoint_count := 0
	var checkpoint_succeeds := true


	func is_dirty() -> bool:
		return dirty


	func checkpoint() -> GDSQLCheckpointResult:
		checkpoint_count += 1
		var result := GDSQLCheckpointResult.new()
		if checkpoint_succeeds:
			dirty = false
		else:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(&"TEST_CHECKPOINT_FAILED", "Checkpoint failed."),
			)
		return result
