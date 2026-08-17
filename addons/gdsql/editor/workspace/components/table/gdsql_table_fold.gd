@tool
extends FoldableContainer
## Foldable editor for one existing table definition.

signal changed

const INDEX_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/index/gdsql_index_draft_row.tscn"
)
const INDEX_PROPERTY_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/index/gdsql_index_property_row.tscn"
)

var table_name: StringName
var _table: GDSQLTableDefinition
var _dropped_indexes: Dictionary[StringName, bool] = { }

@onready var _columns: GDSQLEditorColumnEditor = %Columns


func _ready() -> void:
	%AddColumn.pressed.connect(_add_column)
	%AddIndex.pressed.connect(_add_index)
	_columns.changed.connect(changed.emit)


func configure(table: GDSQLTableDefinition, inspection: GDSQLTableInspection) -> void:
	_table = table
	table_name = table.name
	_dropped_indexes.clear()
	title = String(table.name)
	%Summary.text = "%d rows · %d columns · %d indexes" % [
		inspection.row_count,
		table.columns.size(),
		table.indexes.size() + 1,
	]
	_render_indexes(table)
	_columns.configure_existing(table)
	for child in %NewIndexes.get_children():
		%NewIndexes.remove_child(child)
		child.queue_free()


func build_change() -> GDSQLEditorTableChange:
	var alterations: Array[GDSQLTableAlteration] = []
	for index_name in _dropped_indexes:
		if _dropped_indexes[index_name]:
			alterations.append(GDSQLTableAlteration.drop_index(index_name))
	alterations.append_array(_columns.build_alterations())
	for row in %NewIndexes.get_children():
		alterations.append(
			GDSQLTableAlteration.add_index(row.call("build_definition") as GDSQLIndexDefinition),
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
	return true


func focus() -> void:
	folded = false


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


func _set_index_dropped(dropped: bool, index_name: StringName) -> void:
	_dropped_indexes[index_name] = dropped
	changed.emit()


func _add_column() -> void:
	_columns.add_draft_column()


func _add_index() -> void:
	var row := INDEX_DRAFT_SCENE.instantiate() as Control
	%NewIndexes.add_child(row)
	row.connect("changed", changed.emit)
	row.connect("remove_requested", _remove_draft.bind(%NewIndexes))
	changed.emit()


func _remove_draft(row: Control, parent: Control) -> void:
	parent.remove_child(row)
	row.queue_free()
	changed.emit()


func _has_column(column_name: StringName) -> bool:
	return _columns.has_column(column_name)
