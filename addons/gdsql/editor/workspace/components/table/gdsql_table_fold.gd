@tool
extends FoldableContainer
## Foldable editor for one existing table definition.

signal changed
signal data_requested(table_name: StringName)
signal model_requested(table_name: StringName)

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

var table_name: StringName
var _table: GDSQLTableDefinition
var _database: GDSQLDatabaseDefinition
var _dropped_indexes: Dictionary[StringName, bool] = { }
var _dropped_foreign_keys: Dictionary[StringName, bool] = { }

@onready var _columns: GDSQLEditorColumnEditor = %Columns


func _ready() -> void:
	%OpenData.pressed.connect(_request_data)
	%OpenModel.pressed.connect(_request_model)
	%AddColumn.pressed.connect(_add_column)
	%AddIndex.pressed.connect(_add_index)
	%AddForeignKey.pressed.connect(_add_foreign_key)
	_columns.changed.connect(_on_columns_changed)


func configure(
		table: GDSQLTableDefinition,
		inspection: GDSQLTableInspection,
		database: GDSQLDatabaseDefinition,
) -> void:
	_table = table
	_database = database
	table_name = table.name
	_dropped_indexes.clear()
	_dropped_foreign_keys.clear()
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
	for index_name in _dropped_indexes:
		if _dropped_indexes[index_name]:
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
		if not _dropped_indexes.get(definition.name, false):
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
		if not _dropped_foreign_keys.get(definition.name, false):
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
		row.configure(definition)
		row.dropped_changed.connect(_set_index_dropped)


func _render_foreign_keys(table: GDSQLTableDefinition) -> void:
	for child in %ForeignKeys.get_children():
		%ForeignKeys.remove_child(child)
		child.queue_free()
	for definition in table.foreign_keys:
		var row := FOREIGN_KEY_PROPERTY_SCENE.instantiate() \
				as GDSQLEditorForeignKeyPropertyRow
		%ForeignKeys.add_child(row)
		row.configure(definition)
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
		if not _dropped_indexes.get(index.name, false):
			draft.add_index(index)
	for row in %NewIndexes.get_children():
		draft.add_index(row.call("build_definition") as GDSQLIndexDefinition)
	return draft


func _update_foreign_key_indicators() -> void:
	var columns: Array[StringName] = []
	for definition in _table.foreign_keys:
		if _dropped_foreign_keys.get(definition.name, false):
			continue
		var current_name := _columns.resolve_current_name(definition.column)
		if current_name != &"" and current_name not in columns:
			columns.append(current_name)
	for row in %NewForeignKeys.get_children():
		var column_name: StringName = row.call("get_local_column_name")
		if column_name != &"" and column_name not in columns:
			columns.append(column_name)
	_columns.set_foreign_key_columns(columns)
