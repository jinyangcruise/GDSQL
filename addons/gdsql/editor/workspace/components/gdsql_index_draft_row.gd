@tool
extends PanelContainer
## Editable index definition for a new table draft.

signal changed
signal remove_requested(row: Control)

@onready var _name: LineEdit = %Name
@onready var _columns: LineEdit = %Columns
@onready var _unique: CheckBox = %Unique


func _ready() -> void:
	_name.text_changed.connect(changed.emit.unbind(1))
	_columns.text_changed.connect(changed.emit.unbind(1))
	_unique.toggled.connect(changed.emit.unbind(1))
	%Remove.pressed.connect(remove_requested.emit.bind(self))


func build_definition() -> GDSQLIndexDefinition:
	return GDSQLIndexDefinition.new(
		StringName(_name.text.strip_edges()),
		get_columns(),
		_unique.button_pressed,
	)


func get_index_name() -> StringName:
	return StringName(_name.text.strip_edges())


func get_columns() -> Array[StringName]:
	var result: Array[StringName] = []
	for value in _columns.text.split(",", false):
		var column_name := value.strip_edges()
		if not column_name.is_empty():
			result.append(StringName(column_name))
	return result
