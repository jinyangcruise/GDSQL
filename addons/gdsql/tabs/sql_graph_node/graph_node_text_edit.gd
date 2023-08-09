@tool
extends GraphNode

signal node_enabled

@onready var check_button_enable: CheckButton = $CheckButtonEnable
@onready var text_edit: TextEdit = $TextEdit




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
		return text_edit.text if text_edit else ""
	set(val):
		if text_edit:
			text_edit.text = val


func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
