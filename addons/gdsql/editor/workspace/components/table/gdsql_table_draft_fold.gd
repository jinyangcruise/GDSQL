@tool
extends FoldableContainer
## Editable table draft retained by a database document until explicit save.

signal changed
signal remove_requested(draft: Control)

const INDEX_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/index/gdsql_index_draft_row.tscn"
)

@onready var _name: LineEdit = %TableName
@onready var _primary_key: LineEdit = %PrimaryKey
@onready var _columns: GDSQLEditorColumnTree = %Columns
@onready var _indexes: VBoxContainer = %Indexes


func _ready() -> void:
	_name.text_changed.connect(_on_changed.unbind(1))
	_primary_key.text_changed.connect(changed.emit.unbind(1))
	%Timestamps.toggled.connect(changed.emit.unbind(1))
	%AddColumn.pressed.connect(_add_column)
	%AddIndex.pressed.connect(_add_index)
	%RemoveTable.pressed.connect(remove_requested.emit.bind(self))
	_columns.changed.connect(changed.emit)
	for row in _indexes.get_children():
		_connect_index(row)
	folded = false
	%TableName.grab_focus()
	#%TableName.is_editing()


func configure_new() -> void:
	_columns.configure_new_table()
	_on_changed()


func build_definition() -> GDSQLTableDefinition:
	var definition := GDSQLTableDefinition.new(
		StringName(_name.text.strip_edges()),
		StringName(_primary_key.text.strip_edges()),
	)
	for column in _columns.build_definitions():
		definition.add_column(column)
	if %Timestamps.button_pressed:
		definition.add_timestamps()
	for row in _indexes.get_children():
		definition.add_index(row.call("build_definition") as GDSQLIndexDefinition)
	return definition


func is_valid_draft() -> bool:
	return get_validation_errors().is_empty()


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var table_name := _name.text.strip_edges()
	if table_name.is_empty():
		errors.append("A table name is required.")
	elif not table_name.is_valid_identifier():
		errors.append("Table '%s' must be a valid identifier." % table_name)
	var primary_key := StringName(_primary_key.text.strip_edges())
	if primary_key == &"":
		errors.append("Table '%s' requires a primary key." % table_name)
	errors.append_array(_columns.get_validation_errors(primary_key))
	var index_names: Dictionary[StringName, bool] = { }
	for index_row in _indexes.get_children():
		var index_name: StringName = index_row.call("get_index_name")
		if index_name == &"":
			errors.append("Every index requires a name.")
		elif index_names.has(index_name):
			errors.append("Index '%s' is declared more than once." % index_name)
		index_names[index_name] = true
		var index_columns: Array[StringName] = index_row.call("get_columns")
		if index_columns.is_empty():
			errors.append("Index '%s' requires at least one column." % index_name)
		for column_name in index_columns:
			if not _has_column(column_name):
				errors.append(
					"Index '%s' references unknown column '%s'." \
							% [index_name, column_name],
				)
	return errors


func _add_column() -> void:
	_columns.add_draft_column()


func _add_index() -> void:
	var row := INDEX_DRAFT_SCENE.instantiate()
	_indexes.add_child(row)
	_connect_index(row)
	changed.emit()


func _connect_index(row: Control) -> void:
	row.connect("changed", changed.emit)
	row.connect("remove_requested", _remove_index)


func _remove_index(row: Control) -> void:
	_indexes.remove_child(row)
	row.queue_free()
	changed.emit()


func _has_column(column_name: StringName) -> bool:
	return _columns.has_column(column_name) or column_name in [&"created_at", &"updated_at"] \
			and %Timestamps.button_pressed


func _on_changed() -> void:
	title = (
			"New table: %s" % _name.text.strip_edges()
			if not _name.text.strip_edges().is_empty()
			else "New table"
	)
	changed.emit()
