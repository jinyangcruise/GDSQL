@tool
extends GraphNode

signal node_enabled

@onready var option_button: OptionButton = $HBoxContainer/OptionButton
@onready var check_button_enable: CheckButton = $CheckButtonEnable



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
		if option_button:
			return option_button.get_item_text(option_button.selected)
		return ""
	set(val):
		if option_button:
			for i in option_button.item_count:
				if option_button.get_item_text(i) == val:
					option_button.select(i)
					break


func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
