@tool
extends FoldableContainer
## Foldable editor for one existing table definition.

signal changed

const COLUMN_ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_column_property_row.tscn"
)
const COLUMN_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_column_draft_row.tscn"
)
const INDEX_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_index_draft_row.tscn"
)

var table_name: StringName
var _table: GDSQLTableDefinition
var _dropped_indexes: Dictionary[StringName, bool] = { }


func _ready() -> void:
	%AddColumn.pressed.connect(_add_column)
	%AddIndex.pressed.connect(_add_index)


func configure(
		table: GDSQLTableDefinition,
		inspection: GDSQLTableInspection,
) -> void:
	_table = table
	table_name = table.name
	_dropped_indexes.clear()
	title = String(table.name)
	$Content/Summary.text = "%d rows · %d columns · %d indexes" % [
		inspection.row_count,
		table.columns.size(),
		table.indexes.size(),
	]
	%PrimaryKey.text = "Primary key: %s" % table.primary_key
	_render_indexes(table)
	var rows := %Columns
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for column in table.columns:
		var row := COLUMN_ROW_SCENE.instantiate() as Control
		rows.add_child(row)
		row.call("configure", column, column.name == table.primary_key)
		row.connect("changed", changed.emit)
	for child in %NewColumns.get_children():
		%NewColumns.remove_child(child)
		child.queue_free()
	for child in %NewIndexes.get_children():
		%NewIndexes.remove_child(child)
		child.queue_free()


func build_change() -> GDSQLEditorTableChange:
	var alterations: Array[GDSQLTableAlteration] = []
	for index_name in _dropped_indexes:
		if _dropped_indexes[index_name]:
			alterations.append(GDSQLTableAlteration.drop_index(index_name))
	for row in %Columns.get_children():
		for alteration in row.call("build_alterations"):
			alterations.append(alteration)
	for row in %NewColumns.get_children():
		alterations.append(
			GDSQLTableAlteration.add_column(
				row.call("build_definition") as GDSQLColumnDefinition,
			),
		)
	for row in %NewIndexes.get_children():
		alterations.append(
			GDSQLTableAlteration.add_index(
				row.call("build_definition") as GDSQLIndexDefinition,
			),
		)
	return GDSQLEditorTableChange.new(table_name, alterations)


func has_changes() -> bool:
	return not build_change().alterations.is_empty()


func is_valid_draft() -> bool:
	var column_names: Dictionary[StringName, bool] = { }
	for row in %Columns.get_children():
		if not bool(row.call("is_valid_draft")):
			return false
		if bool(row.get("marked_for_removal")):
			continue
		var column_name: StringName = row.call("get_requested_name")
		if column_names.has(column_name):
			return false
		column_names[column_name] = true
	for row in %NewColumns.get_children():
		var column_name: StringName = row.call("get_column_name")
		if not bool(row.call("is_valid_draft")) \
				or column_name == &"" \
				or column_names.has(column_name):
			return false
		column_names[column_name] = true
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
	if table.indexes.is_empty():
		var empty := Label.new()
		empty.text = "Indexes: none"
		%Indexes.add_child(empty)
		return
	for definition in table.indexes:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s (%s)%s" % [
			definition.name,
			", ".join(
				definition.columns.map(
					func(column_name: StringName) -> String:
						return String(column_name),
				),
			),
			" · unique" if definition.unique else "",
		]
		var remove := CheckBox.new()
		remove.text = "Remove"
		remove.toggled.connect(_set_index_dropped.bind(definition.name))
		row.add_child(label)
		row.add_child(remove)
		%Indexes.add_child(row)


func _set_index_dropped(dropped: bool, index_name: StringName) -> void:
	_dropped_indexes[index_name] = dropped
	changed.emit()


func _add_column() -> void:
	var row := COLUMN_DRAFT_SCENE.instantiate() as Control
	%NewColumns.add_child(row)
	row.connect("changed", changed.emit)
	row.connect("remove_requested", _remove_draft.bind(%NewColumns))
	changed.emit()


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
	for row in %Columns.get_children():
		if row.call("get_requested_name") == column_name \
				and not bool(row.get("marked_for_removal")):
			return true
	for row in %NewColumns.get_children():
		if row.call("get_column_name") == column_name:
			return true
	return false
