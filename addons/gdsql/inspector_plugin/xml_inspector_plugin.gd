extends EditorInspectorPlugin

var xml_editor_window: Window

func _can_handle(object: Object) -> bool:
	return object is GXML
	
func _parse_begin(object: Object) -> void:
	var pc = PanelContainer.new()
	var edit_btn = Button.new()
	pc.add_child(edit_btn)
	edit_btn.text = "Edit"
	edit_btn.icon = EditorInterface.get_base_control().get_theme_icon("Edit", "EditorIcons")
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.pressed.connect(_on_edit_btn_pressed.bind(object.resource_path))
	add_custom_control(pc)

func _on_edit_btn_pressed(path: String):
	xml_editor_window.open_file(path)
