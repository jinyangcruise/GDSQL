class_name GDSQLEditorMutationHistory
extends RefCounted
## Bounded session-only Undo/Redo state; execution remains with the controller.

signal changed

var max_entries: int
var _undo_entries: Array[GDSQLEditorMutationHistoryEntry] = []
var _redo_entries: Array[GDSQLEditorMutationHistoryEntry] = []


func _init(history_limit: int = 50) -> void:
	max_entries = maxi(1, history_limit)


func record(entry: GDSQLEditorMutationHistoryEntry) -> GDSQLOperationResult:
	if entry == null or not entry.is_valid():
		return _error(
				&"GDSQL_EDITOR_MUTATION_HISTORY_ENTRY_INVALID",
				"A mutation history entry requires a target and valid row snapshots.",
		)
	_undo_entries.append(entry)
	while _undo_entries.size() > max_entries:
		_undo_entries.pop_front()
	_redo_entries.clear()
	changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = entry
	return result


func can_undo() -> bool:
	return not _undo_entries.is_empty()


func can_redo() -> bool:
	return not _redo_entries.is_empty()


func get_undo_entry() -> GDSQLEditorMutationHistoryEntry:
	return _undo_entries.back() if can_undo() else null


func get_redo_entry() -> GDSQLEditorMutationHistoryEntry:
	return _redo_entries.back() if can_redo() else null


func mark_undone(entry: GDSQLEditorMutationHistoryEntry) -> GDSQLOperationResult:
	if not can_undo() or _undo_entries.back() != entry:
		return _error(
				&"GDSQL_EDITOR_MUTATION_HISTORY_ORDER_INVALID",
				"Only the latest committed mutation can be marked as undone.",
		)
	_redo_entries.append(_undo_entries.pop_back())
	changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = entry
	return result


func mark_redone(entry: GDSQLEditorMutationHistoryEntry) -> GDSQLOperationResult:
	if not can_redo() or _redo_entries.back() != entry:
		return _error(
				&"GDSQL_EDITOR_MUTATION_HISTORY_ORDER_INVALID",
				"Only the latest undone mutation can be marked as redone.",
		)
	_undo_entries.append(_redo_entries.pop_back())
	changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = entry
	return result


func clear() -> void:
	if _undo_entries.is_empty() and _redo_entries.is_empty():
		return
	_undo_entries.clear()
	_redo_entries.clear()
	changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
