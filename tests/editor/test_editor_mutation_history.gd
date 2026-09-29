class_name GDSQLEditorMutationHistoryTest
extends GdUnitTestSuite


func test_records_bounded_entries_and_exposes_latest_undo() -> void:
	var history := GDSQLEditorMutationHistory.new(2)
	var first := _update_entry(1, "Knight", "Paladin")
	var second := _update_entry(2, "Mage", "Wizard")
	var third := _update_entry(3, "Rogue", "Assassin")

	assert_bool(history.record(first).is_successful()).is_true()
	assert_bool(history.record(second).is_successful()).is_true()
	assert_bool(history.record(third).is_successful()).is_true()
	assert_object(history.get_undo_entry()).is_same(third)
	assert_bool(history.mark_undone(third).is_successful()).is_true()
	assert_object(history.get_undo_entry()).is_same(second)
	assert_object(history.get_redo_entry()).is_same(third)


func test_new_mutation_clears_redo_history() -> void:
	var history := GDSQLEditorMutationHistory.new()
	var first := _update_entry(1, "Knight", "Paladin")
	history.record(first)
	history.mark_undone(first)

	history.record(_update_entry(2, "Mage", "Wizard"))

	assert_bool(history.can_undo()).is_true()
	assert_bool(history.can_redo()).is_false()


func test_stack_moves_only_in_latest_entry_order() -> void:
	var history := GDSQLEditorMutationHistory.new()
	var first := _update_entry(1, "Knight", "Paladin")
	var second := _update_entry(2, "Mage", "Wizard")
	history.record(first)
	history.record(second)

	var rejected := history.mark_undone(first)

	assert_bool(rejected.is_successful()).is_false()
	assert_object(history.get_undo_entry()).is_same(second)
	assert_bool(history.can_redo()).is_false()


func test_entry_owns_row_snapshot_copies() -> void:
	var before: Array[GDSQLRowRecord] = [GDSQLRowRecord.new({&"id": 1, &"name": "Knight"})]
	var after: Array[GDSQLRowRecord] = [GDSQLRowRecord.new({&"id": 1, &"name": "Paladin"})]
	var entry := GDSQLEditorMutationHistoryEntry.new(
		&"content",
		&"game_content",
		&"heroes",
		GDSQLEditorMutationHistoryEntry.Operation.UPDATE,
		before,
		after,
	)
	before[0].set_value(&"name", "Changed outside")
	after[0].set_value(&"name", "Changed outside")

	assert_str(String(entry.before_rows[0].get_value(&"name"))).is_equal("Knight")
	assert_str(String(entry.after_rows[0].get_value(&"name"))).is_equal("Paladin")
	assert_str(entry.get_summary()).is_equal("Update 1 row(s) in heroes")


func test_rejects_incomplete_entries() -> void:
	var history := GDSQLEditorMutationHistory.new()
	var entry := GDSQLEditorMutationHistoryEntry.new()

	assert_bool(history.record(entry).is_successful()).is_false()
	assert_bool(history.can_undo()).is_false()


func _update_entry(
		identity: int,
		before_name: String,
		after_name: String,
) -> GDSQLEditorMutationHistoryEntry:
	var before: Array[GDSQLRowRecord] = [
		GDSQLRowRecord.new({&"id": identity, &"name": before_name}),
	]
	var after: Array[GDSQLRowRecord] = [
		GDSQLRowRecord.new({&"id": identity, &"name": after_name}),
	]
	return GDSQLEditorMutationHistoryEntry.new(
		&"content",
		&"game_content",
		&"heroes",
		GDSQLEditorMutationHistoryEntry.Operation.UPDATE,
		before,
		after,
	)
