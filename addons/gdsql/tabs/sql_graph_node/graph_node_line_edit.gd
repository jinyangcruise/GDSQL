@tool
extends GraphNode

signal node_enabled

@onready var check_button_enable: CheckButton = $CheckButtonEnable
@onready var line_edit: LineEdit = $LineEdit


var enabled: bool:
	get:
		return check_button_enable and check_button_enable.button_pressed
	set(val):
		if check_button_enable:
			check_button_enable.button_pressed = val
			if val:
				node_enabled.emit()
		
var value: Variant:
	get:
		return line_edit.text if line_edit else ""
	set(val):
		if line_edit:
			line_edit.text = val


func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
