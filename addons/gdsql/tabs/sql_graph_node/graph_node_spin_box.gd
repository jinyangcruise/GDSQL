@tool
extends GraphNode

signal node_enabled

@onready var check_button_enable: CheckButton = $CheckButtonEnable
@onready var spin_box: SpinBox = $SpinBox




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
		return spin_box.value if spin_box else 0
	set(val):
		if spin_box:
			spin_box.value = val


func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
