@tool
extends EditorPlugin

const MainPanel = preload("res://addons/gdsql/index.tscn")

var main_panel_instance
var dictionary_object_inspector_plugin
var resource_format_loader_xml: ResourceFormatLoaderXML
var xml_inspector_plugin
var xml_editor_window

#region Singleton
var conf_manager: Node
var gdsql_workbench_manager: Node
#endregion

func _enter_tree():
	# 注册配置单例，让非插件范围的代码能使用ConfManager
	add_autoload_singleton("ConfManager", "res://addons/gdsql/database/conf_manager.gd")
	
	# 注册配置单例，让插件范围内的代码能使用ConfManager（需通过类型转换为ConfManagerClass来实现编辑器代码提示）
	if not Engine.has_singleton("ConfManager"):
		conf_manager = preload("res://addons/gdsql/database/conf_manager.gd").new()
		Engine.register_singleton("ConfManager", conf_manager)
	
	# 注册配置单例，让插件范围内的代码能使用GDSQLWorkbenchManager（需通过类型转换为GDSQLWorkbenchManageClass来实现编辑器代码提示）
	if not Engine.has_singleton("GDSQLWorkbenchManager"):
		gdsql_workbench_manager = preload("res://addons/gdsql/singletons/gdsql_workbench_manager.gd").new()
		gdsql_workbench_manager.set_translation_domain("godot.editor")
		Engine.register_singleton("GDSQLWorkbenchManager", gdsql_workbench_manager)
	
	# 特别需求，让检查器能够查看DictionaryObject
	# EditorInspectorPlugin is a resource, so we use `new()` instead of `instance()`.
	dictionary_object_inspector_plugin = preload("res://addons/gdsql/inspector_plugin/dictionary_object_inspector_plugin.gd").new()
	add_inspector_plugin(dictionary_object_inspector_plugin)
	
	# XML resource load NOTICE gdscript写的不需要手动调用
	#resource_format_loader_xml = ResourceFormatLoaderXML.new()
	#ResourceLoader.add_resource_format_loader(resource_format_loader_xml)
	
	# XML Editor 编辑器。由于ResourceFormatLoaderXML增加了@tool，导致引擎自带的编辑器
	# 无法打开xml文件了，所以自己做了一个
	xml_editor_window = preload("res://addons/gdsql/gxml/editor/xml_editor_window.tscn").instantiate()
	EditorInterface.get_base_control().add_child(xml_editor_window)
	xml_inspector_plugin = preload("res://addons/gdsql/inspector_plugin/xml_inspector_plugin.gd").new()
	xml_inspector_plugin.xml_editor_window = xml_editor_window
	add_tool_menu_item("XML Editor", xml_editor_window.open_file.bind(""))
	add_inspector_plugin(xml_inspector_plugin)
	
	# 进入界面
	main_panel_instance = MainPanel.instantiate()
	Engine.get_singleton("GDSQLWorkbenchManager").main_panel = main_panel_instance
	# Add the main panel to the editor's main viewport.
	EditorInterface.get_editor_main_screen().add_child(main_panel_instance)
	# Hide the main panel. Very much required.
	_make_visible(false)
	
	

func _exit_tree():
	#ResourceLoader.remove_resource_format_loader(resource_format_loader_xml)
	if main_panel_instance:
		main_panel_instance.queue_free()
	if xml_editor_window:
		xml_editor_window.queue_free()
	remove_tool_menu_item("XML Editor")
	Engine.get_singleton("GDSQLWorkbenchManager").main_panel = null
	if dictionary_object_inspector_plugin:
		remove_inspector_plugin(dictionary_object_inspector_plugin)
	if xml_inspector_plugin:
		remove_inspector_plugin(xml_inspector_plugin)
	if Engine.has_singleton("ConfManager"):
		Engine.unregister_singleton("ConfManager")
		conf_manager.queue_free()
	if Engine.has_singleton("GDSQLWorkbenchManager"):
		Engine.unregister_singleton("GDSQLWorkbenchManager")
		gdsql_workbench_manager.queue_free()
		
	
func _has_main_screen():
	return true


func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name():
	return "GDSQL"


func _get_plugin_icon():
	return EditorInterface.get_base_control().get_theme_icon("ItemList", "EditorIcons")
