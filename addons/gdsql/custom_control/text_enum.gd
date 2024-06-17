@tool
extends HBoxContainer

signal value_changed(new_value: String)

@onready var option_button: OptionButton = $default_layout/OptionButton
@onready var edit_button: Button = $default_layout/edit_button
@onready var custom_value_edit: LineEdit = $edit_custom_layout/custom_value_edit
@onready var accept_button: Button = $edit_custom_layout/accept_button
@onready var cancel_button: Button = $edit_custom_layout/cancel_button
@onready var default_layout: HBoxContainer = $default_layout
@onready var edit_custom_layout: HBoxContainer = $edit_custom_layout

var value: String
var loose_mode: bool = false
var options: Array

func setup(p_options: Array, p_loose_mode: bool):
	loose_mode = p_loose_mode
	options.clear()
	
	if loose_mode:
		option_button.add_item("", options.size() + 1000)
		
	for i in p_options.size():
		options.push_back(p_options[i])
		option_button.add_item(p_options[i], i)
		
	if loose_mode:
		edit_button.show()
		
func _ready() -> void:
	if not edit_button.icon:
		edit_button.icon = get_theme_icon("Edit", "EditorIcons")
	if not accept_button.icon:
		accept_button.icon = get_theme_icon("ImportCheck", "EditorIcons")
	if not cancel_button.icon:
		cancel_button.icon = get_theme_icon("ImportFail", "EditorIcons")
	update_property()
	
func get_selected_text() -> String:
	if option_button.get_selected_id() >= 1000:
		return value
	return option_button.get_item_text(option_button.get_selected_id())
	
func update_property():
	var current_value = value
	var default_option = options.find(current_value)
	
	# The list can change in the loose mode.
	if loose_mode:
		custom_value_edit.set_text(current_value)
		option_button.clear()
		
		# Manually entered value.
		if default_option < 0 and !current_value.is_empty():
			option_button.add_item(current_value, options.size() + 1001)
			option_button.select(0)
			
			option_button.add_separator()
			
		# Add an explicit empty value for clearing the property.
		option_button.add_item("", options.size() + 1000)
		
		for i in options.size():
			option_button.add_item(options[i], i)
			if options[i] == current_value:
				option_button.select(option_button.get_item_count() - 1)
				
	else:
		option_button.select(default_option)
		
func _option_selected(p_which: int) -> void:
	value = option_button.get_item_text(p_which).strip_edges()
	update_property()
	value_changed.emit()


func _edit_custom_value() -> void:
	default_layout.hide()
	edit_custom_layout.show()
	custom_value_edit.grab_focus()


func _custom_value_submitted(p_value: String) -> void:
	value = p_value.strip_edges()
	edit_custom_layout.hide()
	default_layout.show()
	update_property()
	value_changed.emit()

func _custom_value_accepted() -> void:
	value = custom_value_edit.get_text().strip_edges()
	_custom_value_submitted(value)


func _custom_value_canceled() -> void:
	custom_value_edit.set_text(value)
	edit_custom_layout.hide()
	default_layout.show()
	update_property()
