@tool
extends Window

@onready var xml_editor_panel: PanelContainer = $XMLEditorPanel

var inited = false

func _on_close_requested() -> void:
	hide()

func open_file(path: String):
	if not visible:
		if inited:
			popup_centered()
		else:
			popup_centered_ratio(0.6)
			inited = true
			
	xml_editor_panel.open_file(path)
