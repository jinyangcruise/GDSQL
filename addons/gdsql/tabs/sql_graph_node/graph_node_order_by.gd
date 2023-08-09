@tool
extends GraphNode

signal node_enabled

@onready var check_button_enable: CheckButton = $VBoxContainer/CheckButtonEnable
@onready var option_button: OptionButton = $VBoxContainer/HBoxContainer/OptionButton
@onready var line_edit: LineEdit = $VBoxContainer/HBoxContainer/LineEdit



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
			return [line_edit.text, option_button.get_item_text(option_button.selected)]
		return ["", "ASC"]
	set(val):
		if option_button and line_edit:
			line_edit.text = val[0]
			for i in option_button.item_count:
				if option_button.get_item_text(i) == val[1]:
					option_button.select(i)
					break


func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
