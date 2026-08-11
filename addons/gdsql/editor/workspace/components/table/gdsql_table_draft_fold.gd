@tool
extends FoldableContainer
## Editable table draft retained by a database document until explicit save.

signal changed
signal remove_requested(draft: Control)

const COLUMN_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_column_draft_row.tscn"
)
const INDEX_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_index_draft_row.tscn"
)

@onready var _name: LineEdit = %TableName
@onready var _primary_key: LineEdit = %PrimaryKey
@onready var _columns: VBoxContainer = %Columns
@onready var _indexes: VBoxContainer = %Indexes


func _ready() -> void:
	_name.text_changed.connect(_on_changed.unbind(1))
	_primary_key.text_changed.connect(changed.emit.unbind(1))
	%Timestamps.toggled.connect(changed.emit.unbind(1))
	%AddColumn.pressed.connect(_add_column)
	%AddIndex.pressed.connect(_add_index)
	%RemoveTable.pressed.connect(remove_requested.emit.bind(self))
	for row in _columns.get_children():
		_connect_row(row)
	for row in _indexes.get_children():
		_connect_index(row)
	folded = false
	%TableName.grab_focus()
	#%TableName.is_editing()


func configure_new() -> void:
	var first_row := _columns.get_child(0)
	first_row.call("configure_primary_key")
	_on_changed()


func build_definition() -> GDSQLTableDefinition:
	var definition := GDSQLTableDefinition.new(
		StringName(_name.text.strip_edges()),
		StringName(_primary_key.text.strip_edges()),
	)
	for row in _columns.get_children():
		definition.add_column(row.call("build_definition") as GDSQLColumnDefinition)
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
	var column_names: Dictionary[StringName, bool] = { }
	var auto_increment_columns := 0
	for row in _columns.get_children():
		var column_error: String = row.call("get_validation_error")
		if not column_error.is_empty():
			errors.append(column_error)
		var column_name: StringName = row.call("get_column_name")
		if column_name != &"" and column_names.has(column_name):
			errors.append("Column '%s' is declared more than once." % column_name)
		column_names[column_name] = true
		var definition := row.call("build_definition") as GDSQLColumnDefinition
		if definition != null and definition.auto_increment:
			auto_increment_columns += 1
	if primary_key != &"" and not column_names.has(primary_key):
		errors.append("Primary key '%s' must reference a declared column." % primary_key)
	if auto_increment_columns > 1:
		errors.append("Only one auto-increment column is supported.")
	elif auto_increment_columns == 1:
		for row in _columns.get_children():
			var definition := row.call("build_definition") as GDSQLColumnDefinition
			if definition.auto_increment and definition.name != primary_key:
				errors.append("Auto-increment is supported only on the primary key.")
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
	var row := COLUMN_DRAFT_SCENE.instantiate()
	_columns.add_child(row)
	_connect_row(row)
	changed.emit()


func _connect_row(row: Control) -> void:
	row.connect("changed", changed.emit)
	row.connect("remove_requested", _remove_column)


func _add_index() -> void:
	var row := INDEX_DRAFT_SCENE.instantiate()
	_indexes.add_child(row)
	_connect_index(row)
	changed.emit()


func _connect_index(row: Control) -> void:
	row.connect("changed", changed.emit)
	row.connect("remove_requested", _remove_index)


func _remove_column(row: Control) -> void:
	if _columns.get_child_count() <= 1:
		return
	_columns.remove_child(row)
	row.queue_free()
	changed.emit()


func _remove_index(row: Control) -> void:
	_indexes.remove_child(row)
	row.queue_free()
	changed.emit()


func _has_column(column_name: StringName) -> bool:
	for row in _columns.get_children():
		if row.call("get_column_name") == column_name:
			return true
	return column_name in [&"created_at", &"updated_at"] \
			and %Timestamps.button_pressed


func _on_changed() -> void:
	title = (
		"New table: %s" % _name.text.strip_edges()
		if not _name.text.strip_edges().is_empty()
		else "New table"
	)
	changed.emit()
