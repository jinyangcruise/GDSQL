@tool
extends FoldableContainer
## Foldable editor for one existing table definition.

signal changed
signal data_requested(table_name: StringName)
signal model_requested(table_name: StringName)
signal reset_requested(table_name: StringName)

const INDEX_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/index/gdsql_index_draft_row.tscn"
)
const INDEX_PROPERTY_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/index/gdsql_index_property_row.tscn"
)
const FOREIGN_KEY_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/foreign_key/gdsql_foreign_key_draft_row.tscn"
)
const FOREIGN_KEY_PROPERTY_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/foreign_key/gdsql_foreign_key_property_row.tscn"
)
const COLUMN_ACTION_REMOVE := 0
const COLUMN_ACTION_RESTORE := 1

var table_name: StringName
var _table: GDSQLTableDefinition
var _database: GDSQLDatabaseDefinition
var _row_count := 0
var _dropped_indexes: Dictionary[StringName, bool] = { }
var _dropped_foreign_keys: Dictionary[StringName, bool] = { }
var _column_dropped_indexes: Dictionary[StringName, bool] = { }
var _column_dropped_foreign_keys: Dictionary[StringName, bool] = { }
var _context_column: GDSQLEditorColumnDraft

@onready var _columns: GDSQLEditorColumnEditor = %Columns


func _ready() -> void:
	%OpenData.pressed.connect(_request_data)
	%OpenModel.pressed.connect(_request_model)
	%ResetData.pressed.connect(_request_reset)
	%AddColumn.pressed.connect(_add_column)
	%ColumnActions.id_pressed.connect(_on_column_context_action)
	%ColumnRemovalConfirmation.confirmed.connect(_confirm_column_removal)
	%AddIndex.pressed.connect(_add_index)
	%AddForeignKey.pressed.connect(_add_foreign_key)
	_columns.changed.connect(_on_columns_changed)
	_columns.column_context_requested.connect(_show_column_context)


func configure(
		table: GDSQLTableDefinition,
		inspection: GDSQLTableInspection,
		database: GDSQLDatabaseDefinition,
) -> void:
	_table = table
	_database = database
	_row_count = inspection.row_count
	table_name = table.name
	_dropped_indexes.clear()
	_dropped_foreign_keys.clear()
	_column_dropped_indexes.clear()
	_column_dropped_foreign_keys.clear()
	title = String(table.name)
	%Summary.text = "%d rows · %d columns · %d indexes" % [
		inspection.row_count,
		table.columns.size(),
		table.indexes.size() + 1,
	]
	_render_indexes(table)
	_render_foreign_keys(table)
	_columns.configure_existing(table)
	for child in %NewIndexes.get_children():
		%NewIndexes.remove_child(child)
		child.queue_free()
	for child in %NewForeignKeys.get_children():
		%NewForeignKeys.remove_child(child)
		child.queue_free()
	_update_foreign_key_indicators()


func build_change() -> GDSQLEditorTableChange:
	var alterations: Array[GDSQLTableAlteration] = []
	for constraint_name in _dropped_foreign_keys:
		if _dropped_foreign_keys[constraint_name]:
			alterations.append(GDSQLTableAlteration.drop_foreign_key(constraint_name))
	for constraint_name in _column_dropped_foreign_keys:
		if _column_dropped_foreign_keys[constraint_name] \
				and not _dropped_foreign_keys.get(constraint_name, false):
			alterations.append(GDSQLTableAlteration.drop_foreign_key(constraint_name))
	for index_name in _dropped_indexes:
		if _dropped_indexes[index_name]:
			alterations.append(GDSQLTableAlteration.drop_index(index_name))
	for index_name in _column_dropped_indexes:
		if _column_dropped_indexes[index_name] \
				and not _dropped_indexes.get(index_name, false):
			alterations.append(GDSQLTableAlteration.drop_index(index_name))
	alterations.append_array(_columns.build_alterations())
	for row in %NewIndexes.get_children():
		alterations.append(
			GDSQLTableAlteration.add_index(row.call("build_definition") as GDSQLIndexDefinition),
		)
	for row in %NewForeignKeys.get_children():
		alterations.append(
			GDSQLTableAlteration.add_foreign_key(
				row.call("build_definition") as GDSQLForeignKeyDefinition,
			),
		)
	return GDSQLEditorTableChange.new(table_name, alterations)


func has_changes() -> bool:
	return not build_change().alterations.is_empty()


func is_valid_draft() -> bool:
	if not _columns.get_validation_errors(_table.primary_key).is_empty():
		return false
	var index_names: Dictionary[StringName, bool] = { }
	for definition in _table.indexes:
		if not _is_index_dropped(definition.name):
			index_names[definition.name] = true
	for row in %NewIndexes.get_children():
		var columns: Array[StringName] = row.call("get_columns")
		var index_name: StringName = row.call("get_index_name")
		if index_name == &"" or columns.is_empty() or index_names.has(index_name):
			return false
		index_names[index_name] = true
		for column_name in columns:
			if not _has_column(column_name):
				return false
	var foreign_key_names: Dictionary[StringName, bool] = { }
	for definition in _table.foreign_keys:
		if not _is_foreign_key_dropped(definition.name):
			foreign_key_names[definition.name] = true
	for row in %NewForeignKeys.get_children():
		if not row.call("get_validation_errors").is_empty():
			return false
		var constraint_name: StringName = row.call("get_constraint_name")
		if foreign_key_names.has(constraint_name):
			return false
		foreign_key_names[constraint_name] = true
	return true


func focus() -> void:
	folded = false


func _request_data() -> void:
	data_requested.emit(table_name)


func _request_model() -> void:
	model_requested.emit(table_name)


func _request_reset() -> void:
	reset_requested.emit(table_name)


func matches_search(query: String) -> bool:
	if query.is_empty() or String(table_name).to_lower().contains(query):
		return true
	if _table != null:
		for column in _table.columns:
			if String(column.name).to_lower().contains(query):
				return true
	return false


func _render_indexes(table: GDSQLTableDefinition) -> void:
	for child in %Indexes.get_children():
		%Indexes.remove_child(child)
		child.queue_free()
	var primary_row := INDEX_PROPERTY_SCENE.instantiate() as GDSQLEditorIndexPropertyRow
	%Indexes.add_child(primary_row)
	primary_row.configure_primary(table.primary_key)
	for definition in table.indexes:
		var row := INDEX_PROPERTY_SCENE.instantiate() as GDSQLEditorIndexPropertyRow
		%Indexes.add_child(row)
		row.configure(
			definition,
			_is_index_dropped(definition.name),
			bool(_column_dropped_indexes.get(definition.name, false)),
		)
		row.dropped_changed.connect(_set_index_dropped)


func _render_foreign_keys(table: GDSQLTableDefinition) -> void:
	for child in %ForeignKeys.get_children():
		%ForeignKeys.remove_child(child)
		child.queue_free()
	for definition in table.foreign_keys:
		var row := FOREIGN_KEY_PROPERTY_SCENE.instantiate() \
				as GDSQLEditorForeignKeyPropertyRow
		%ForeignKeys.add_child(row)
		row.configure(
			definition,
			_is_foreign_key_dropped(definition.name),
			bool(_column_dropped_foreign_keys.get(definition.name, false)),
		)
		row.dropped_changed.connect(_set_foreign_key_dropped)


func _set_index_dropped(dropped: bool, index_name: StringName) -> void:
	_dropped_indexes[index_name] = dropped
	_refresh_foreign_key_context()
	changed.emit()


func _set_foreign_key_dropped(dropped: bool, constraint_name: StringName) -> void:
	_dropped_foreign_keys[constraint_name] = dropped
	_update_foreign_key_indicators()
	changed.emit()


func _add_column() -> void:
	_columns.add_draft_column()


func _show_column_context(column_draft: GDSQLEditorColumnDraft) -> void:
	_context_column = column_draft
	%ColumnActions.clear()
	if column_draft.is_primary:
		%ColumnActions.add_item("Primary key cannot be removed", COLUMN_ACTION_REMOVE)
		%ColumnActions.set_item_disabled(0, true)
	elif column_draft.remove:
		%ColumnActions.add_item("Restore Column", COLUMN_ACTION_RESTORE)
	else:
		%ColumnActions.add_item("Remove Column…", COLUMN_ACTION_REMOVE)
	%ColumnActions.position = DisplayServer.mouse_get_position()
	%ColumnActions.popup()


func _on_column_context_action(action_id: int) -> void:
	if _context_column == null or _context_column.is_primary:
		return
	if action_id == COLUMN_ACTION_RESTORE:
		_columns.set_column_removal(_context_column, false, false)
		_sync_column_drop_dependencies()
		_refresh_dependency_rows()
		changed.emit()
		return
	if action_id != COLUMN_ACTION_REMOVE:
		return
	var drafts: Array[GDSQLEditorColumnDraft] = [_context_column]
	var incoming := _incoming_foreign_key_dependencies(_original_column_names(drafts))
	%ColumnRemovalConfirmation.dialog_text = _column_removal_message(_context_column)
	%ColumnRemovalConfirmation.title = (
		"Cannot Remove Column"
		if not incoming.is_empty() else "Remove Column"
	)
	%ColumnRemovalConfirmation.get_ok_button().disabled = not incoming.is_empty()
	%ColumnRemovalConfirmation.get_ok_button().tooltip_text = (
		"Remove and save the listed foreign keys first."
		if not incoming.is_empty() else ""
	)
	%ColumnRemovalConfirmation.popup_centered(Vector2i(620, 330))


func _confirm_column_removal() -> void:
	if _context_column == null or _context_column.is_primary:
		return
	_columns.set_column_removal(_context_column, true, false)
	_discard_dependent_constraint_drafts([_context_column.get_column_name()])
	_sync_column_drop_dependencies()
	_refresh_dependency_rows()
	changed.emit()


func _column_removal_message(draft: GDSQLEditorColumnDraft) -> String:
	var original_names: Array[StringName] = []
	var current_names: Array[StringName] = [draft.get_column_name()]
	if draft.original != null:
		original_names.append(draft.original.name)
	var lines: Array[String] = [
		"Stage removal of column '%s' from '%s'?" % [draft.get_column_name(), table_name],
	]
	if not original_names.is_empty():
		lines.append(
			"Saving will permanently delete its values from %d stored row(s)." % _row_count,
		)
	var local_indexes := _dependent_index_names(original_names)
	if not local_indexes.is_empty():
		lines.append("Dependent indexes also staged for removal: %s." % _join_names(local_indexes))
	var local_keys := _dependent_foreign_key_names(original_names)
	if not local_keys.is_empty():
		lines.append("Local foreign keys also staged for removal: %s." % _join_names(local_keys))
	var draft_dependencies := _dependent_draft_names(current_names)
	if not draft_dependencies.is_empty():
		lines.append("Unsaved dependent constraints will be discarded: %s." % ", ".join(draft_dependencies))
	var incoming := _incoming_foreign_key_dependencies(original_names)
	if not incoming.is_empty():
		lines.append(
			"Blocked by foreign keys in other tables: %s. Remove and save those constraints first." \
					% ", ".join(incoming),
		)
	lines.append("Right-click the column again to restore it before Save Changes.")
	return "\n\n".join(lines)


func _original_column_names(
		drafts: Array[GDSQLEditorColumnDraft],
) -> Array[StringName]:
	var names: Array[StringName] = []
	for draft in drafts:
		if draft.original != null:
			names.append(draft.original.name)
	return names


func _sync_column_drop_dependencies() -> void:
	_column_dropped_indexes.clear()
	_column_dropped_foreign_keys.clear()
	var removed := _columns.get_removed_original_columns()
	for name in _dependent_index_names(removed):
		_column_dropped_indexes[name] = true
	for name in _dependent_foreign_key_names(removed):
		_column_dropped_foreign_keys[name] = true


func _dependent_index_names(column_names: Array[StringName]) -> Array[StringName]:
	var names: Array[StringName] = []
	for definition in _table.indexes:
		for column_name in column_names:
			if definition.columns.has(column_name):
				names.append(definition.name)
				break
	return names


func _dependent_foreign_key_names(column_names: Array[StringName]) -> Array[StringName]:
	var names: Array[StringName] = []
	for definition in _table.foreign_keys:
		if definition.column in column_names \
				or (
						definition.referenced_table == table_name \
						and definition.referenced_column in column_names
				):
			names.append(definition.name)
	return names


func _incoming_foreign_key_dependencies(column_names: Array[StringName]) -> Array[String]:
	var dependencies: Array[String] = []
	for source_table in _database.tables:
		if source_table.name == table_name:
			continue
		for definition in source_table.foreign_keys:
			if definition.referenced_table == table_name \
					and definition.referenced_column in column_names:
				dependencies.append("%s.%s (%s)" % [
					source_table.name,
					definition.column,
					definition.name,
				])
	return dependencies


func _dependent_draft_names(column_names: Array[StringName]) -> Array[String]:
	var names: Array[String] = []
	for row in %NewIndexes.get_children():
		for column_name in row.call("get_columns") as Array[StringName]:
			if column_name in column_names:
				names.append("index %s" % row.call("get_index_name"))
				break
	for row in %NewForeignKeys.get_children():
		var definition := row.call("build_definition") as GDSQLForeignKeyDefinition
		if definition.column in column_names \
				or (
						definition.referenced_table == table_name \
						and definition.referenced_column in column_names
				):
			names.append("foreign key %s" % definition.name)
	return names


func _discard_dependent_constraint_drafts(removed_current: Array[StringName]) -> void:
	for row in %NewIndexes.get_children():
		var remove := false
		for column_name in row.call("get_columns") as Array[StringName]:
			remove = remove or column_name in removed_current
		if remove:
			%NewIndexes.remove_child(row)
			row.queue_free()
	for row in %NewForeignKeys.get_children():
		var definition := row.call("build_definition") as GDSQLForeignKeyDefinition
		if definition.column in removed_current \
				or (
						definition.referenced_table == table_name \
						and definition.referenced_column in removed_current
				):
			%NewForeignKeys.remove_child(row)
			row.queue_free()


func _refresh_dependency_rows() -> void:
	_render_indexes(_table)
	_render_foreign_keys(_table)
	_refresh_foreign_key_context()
	_update_foreign_key_indicators()


func _is_index_dropped(index_name: StringName) -> bool:
	return bool(_dropped_indexes.get(index_name, false)) \
			or bool(_column_dropped_indexes.get(index_name, false))


func _is_foreign_key_dropped(constraint_name: StringName) -> bool:
	return bool(_dropped_foreign_keys.get(constraint_name, false)) \
			or bool(_column_dropped_foreign_keys.get(constraint_name, false))


func _join_names(names: Array[StringName]) -> String:
	var values: Array[String] = []
	for name in names:
		values.append(String(name))
	return ", ".join(values)


func _add_index() -> void:
	var row := INDEX_DRAFT_SCENE.instantiate() as Control
	%NewIndexes.add_child(row)
	row.connect("changed", _on_indexes_changed)
	row.connect("remove_requested", _remove_draft.bind(%NewIndexes))
	changed.emit()


func _add_foreign_key() -> void:
	var row := FOREIGN_KEY_DRAFT_SCENE.instantiate() as GDSQLEditorForeignKeyDraftRow
	%NewForeignKeys.add_child(row)
	row.configure(_database, _build_draft_table())
	row.changed.connect(_on_foreign_key_changed)
	row.remove_requested.connect(_remove_draft.bind(%NewForeignKeys))
	row.focus_local_column.call_deferred()
	_update_foreign_key_indicators()
	changed.emit()


func _remove_draft(row: Control, parent: Control) -> void:
	parent.remove_child(row)
	row.queue_free()
	_refresh_after_draft_removal.call_deferred()
	changed.emit()


func _has_column(column_name: StringName) -> bool:
	return _columns.has_column(column_name)


func _on_columns_changed() -> void:
	_refresh_foreign_key_context()
	_update_foreign_key_indicators()
	changed.emit()


func _on_foreign_key_changed() -> void:
	_update_foreign_key_indicators()
	changed.emit()


func _on_indexes_changed() -> void:
	_refresh_foreign_key_context()
	changed.emit()


func _refresh_after_draft_removal() -> void:
	_refresh_foreign_key_context()
	_update_foreign_key_indicators()


func _refresh_foreign_key_context() -> void:
	var source := _build_draft_table()
	for row in %NewForeignKeys.get_children():
		row.call("refresh_context", _database, source)


func _build_draft_table() -> GDSQLTableDefinition:
	var draft := GDSQLTableDefinition.new(table_name, _columns.get_primary_key_name())
	for column in _columns.build_definitions():
		draft.add_column(column)
	for index in _table.indexes:
		if not _is_index_dropped(index.name):
			draft.add_index(index)
	for row in %NewIndexes.get_children():
		draft.add_index(row.call("build_definition") as GDSQLIndexDefinition)
	return draft


func _update_foreign_key_indicators() -> void:
	var columns: Array[StringName] = []
	for definition in _table.foreign_keys:
		if _is_foreign_key_dropped(definition.name):
			continue
		var current_name := _columns.resolve_current_name(definition.column)
		if current_name != &"" and current_name not in columns:
			columns.append(current_name)
	for row in %NewForeignKeys.get_children():
		var column_name: StringName = row.call("get_local_column_name")
		if column_name != &"" and column_name not in columns:
			columns.append(column_name)
	_columns.set_foreign_key_columns(columns)
