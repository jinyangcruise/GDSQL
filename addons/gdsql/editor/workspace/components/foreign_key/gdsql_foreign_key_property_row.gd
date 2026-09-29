@tool
class_name GDSQLEditorForeignKeyPropertyRow
extends PanelContainer
## Scene-backed summary/removal row for one existing foreign key.

signal dropped_changed(dropped: bool, constraint_name: StringName)

var constraint_name: StringName
var _configuring := false


func _ready() -> void:
	%Remove.toggled.connect(_on_remove_toggled)


func configure(
		definition: GDSQLForeignKeyDefinition,
		dropped: bool = false,
		locked: bool = false,
) -> void:
	_configuring = true
	constraint_name = definition.name
	%Summary.text = "%s: %s → %s.%s" % [
		definition.name,
		definition.column,
		definition.referenced_table,
		definition.referenced_column,
	]
	%Summary.tooltip_text = "Updates and deletes use RESTRICT while dependent rows exist."
	%Remove.set_pressed_no_signal(dropped)
	%Remove.disabled = locked
	%Remove.tooltip_text = (
		"This foreign key must be removed with its selected column."
		if locked else ""
	)
	_configuring = false


func _on_remove_toggled(enabled: bool) -> void:
	if not _configuring:
		dropped_changed.emit(enabled, constraint_name)
