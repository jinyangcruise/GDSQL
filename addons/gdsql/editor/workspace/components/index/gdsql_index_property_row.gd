@tool
class_name GDSQLEditorIndexPropertyRow
extends PanelContainer
## Scene-backed summary/removal row for one existing index.

signal dropped_changed(dropped: bool, index_name: StringName)

var index_name: StringName
var _configuring := false


func _ready() -> void:
	%Remove.toggled.connect(_on_remove_toggled)


func configure_primary(column_name: StringName) -> void:
	_configuring = true
	index_name = &""
	%Summary.text = "PRIMARY (%s) · unique · automatic" % column_name
	%Summary.tooltip_text = (
		"Primary keys use GDSQL's dedicated primary-key lookup and cannot be removed "
		+ "as a secondary index."
	)
	%Remove.hide()
	_configuring = false


func configure(definition: GDSQLIndexDefinition) -> void:
	_configuring = true
	index_name = definition.name
	%Summary.text = "%s (%s)%s" % [
		definition.name,
		", ".join(
			definition.columns.map(
				func(column_name: StringName) -> String:
					return String(column_name),
			),
		),
		" · unique" if definition.unique else "",
	]
	%Remove.show()
	%Remove.set_pressed_no_signal(false)
	_configuring = false


func _on_remove_toggled(enabled: bool) -> void:
	if not _configuring:
		dropped_changed.emit(enabled, index_name)
