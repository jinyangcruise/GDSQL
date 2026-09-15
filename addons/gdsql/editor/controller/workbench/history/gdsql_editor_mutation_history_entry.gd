class_name GDSQLEditorMutationHistoryEntry
extends RefCounted
## Immutable-in-use row snapshots for one successfully committed editor batch.

enum Operation { INSERT, UPDATE, DELETE }

var registration_name: StringName
var database_name: StringName
var table_name: StringName
var operation: Operation
var before_rows: Array[GDSQLRowRecord] = []
var after_rows: Array[GDSQLRowRecord] = []


func _init(
		target_registration: StringName = &"",
		target_database: StringName = &"",
		target_table: StringName = &"",
		mutation_operation: Operation = Operation.UPDATE,
		previous_rows: Array[GDSQLRowRecord] = [],
		committed_rows: Array[GDSQLRowRecord] = [],
) -> void:
	registration_name = target_registration
	database_name = target_database
	table_name = target_table
	operation = mutation_operation
	before_rows = _duplicate_rows(previous_rows)
	after_rows = _duplicate_rows(committed_rows)


func is_valid() -> bool:
	if registration_name == &"" or database_name == &"" or table_name == &"":
		return false
	match operation:
		Operation.INSERT:
			return before_rows.is_empty() and not after_rows.is_empty()
		Operation.UPDATE:
			return not before_rows.is_empty() and before_rows.size() == after_rows.size()
		Operation.DELETE:
			return not before_rows.is_empty() and after_rows.is_empty()
	return false


func get_summary() -> String:
	var count := after_rows.size() if operation == Operation.INSERT else before_rows.size()
	return "%s %d row(s) in %s" % [_operation_label(), count, table_name]


func duplicate_before_rows() -> Array[GDSQLRowRecord]:
	return _duplicate_rows(before_rows)


func duplicate_after_rows() -> Array[GDSQLRowRecord]:
	return _duplicate_rows(after_rows)


func _operation_label() -> String:
	match operation:
		Operation.INSERT:
			return "Insert"
		Operation.UPDATE:
			return "Update"
		Operation.DELETE:
			return "Delete"
	return "Mutate"


static func _duplicate_rows(rows: Array[GDSQLRowRecord]) -> Array[GDSQLRowRecord]:
	var copies: Array[GDSQLRowRecord] = []
	for row in rows:
		copies.append(row.duplicate_record())
	return copies
