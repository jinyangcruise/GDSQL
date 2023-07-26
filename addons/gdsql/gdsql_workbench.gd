@tool
extends EditorPlugin

const MainPanel = preload("res://addons/gdsql/index.tscn")

var main_panel_instance
var dictionay_object_inspector_plugin

func _enter_tree():
	main_panel_instance = MainPanel.instantiate()
	# Add the main panel to the editor's main viewport.
	get_editor_interface().get_editor_main_screen().add_child(main_panel_instance)
	# Hide the main panel. Very much required.
	_make_visible(false)
	
	# 特别需求
	# EditorInspectorPlugin is a resource, so we use `new()` instead of `instance()`.
	dictionay_object_inspector_plugin = preload("res://addons/gdsql/dictionary_object_inspector_plugin.gd").new()
	add_inspector_plugin(dictionay_object_inspector_plugin)
	
	main_panel_instance.inspect_object.connect(func(object: Object, for_property: String, inspector_only: bool):
		get_editor_interface().inspect_object(object, for_property, inspector_only)
	)


func _exit_tree():
	if main_panel_instance:
		main_panel_instance.queue_free()
	if dictionay_object_inspector_plugin:
		remove_inspector_plugin(dictionay_object_inspector_plugin)

func _has_main_screen():
	return true


func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name():
	return "GDSQL"


func _get_plugin_icon():
	return get_editor_interface().get_base_control().get_theme_icon("ItemList", "EditorIcons")
