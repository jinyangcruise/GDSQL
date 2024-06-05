@tool
extends Window

@onready var xml_editor_panel: PanelContainer = $XMLEditorPanel

var inited = false

func _on_close_requested() -> void:
	hide()

func open_file(path: String):
	if visible:
		grab_focus() # TODO FIXME WAIT_FOR_UPDATE which is useless in 4.3.dev6
	else:
		if inited:
			popup_centered()
		else:
			popup_centered_ratio(0.6)
			inited = true
			
	if path != "":
		xml_editor_panel.open_file(path)
