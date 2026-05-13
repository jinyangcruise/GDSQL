@tool
extends EditorPlugin

## Icon already has plugin name, so we give it an invisible name.
## We can use ramdom combinations of invisible characters.
const PLUGIN_NAME = "\u200e\u200f\u2060"
const MainPanel = preload("res://addons/gdsql/index.tscn")

var main_panel_instance
var dictionary_object_inspector_plugin
var resource_format_loader_xml: ResourceFormatLoaderXML
var xml_inspector_plugin
var xml_editor_window

func _enter_tree():
	set_up_localization()
	
	var err = init_settings()
	if err != OK:
		return
		
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
	get_window().theme_changed.connect(xml_editor_window.theme_changed.emit)
	
	# 支持双击或右键打开.gdmappergraph文件跳转到workbench
	bind_file_system_dock_for_gdmappergraph()
	
	# 进入界面
	main_panel_instance = MainPanel.instantiate()
	GDSQL.WorkbenchManager.main_panel = main_panel_instance
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
	if dictionary_object_inspector_plugin:
		remove_inspector_plugin(dictionary_object_inspector_plugin)
	if xml_inspector_plugin:
		remove_inspector_plugin(xml_inspector_plugin)
	GDSQL._clear()
	
func _has_main_screen():
	return true
	
func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible
		
func _get_plugin_name():
	return PLUGIN_NAME
	
func _get_plugin_icon():
	return load("res://addons/gdsql/img/gdsql_text_icon.svg")
	
func bind_file_system_dock_for_gdmappergraph():
	var fs_dock = EditorInterface.get_file_system_dock()
	# popup_menu
	for i in fs_dock.get_children(true):
		if i is PopupMenu:
			i.index_pressed.connect(_on_file_system_dock_popup_menu_idex_pressed)
			
	var trees = fs_dock.find_children("@Tree*", "Tree", true, false)
	var file_tree
	for tree: Tree in trees:
		if tree.accessibility_name == tr("Directories"):
			file_tree = tree
			break
			
	if not file_tree:
		push_warning("Cannot find FileSystemTree in file system dock.")
		return
		
	file_tree.item_activated.connect(func():
		var selected = file_tree.get_selected()
		if selected:
			var path = selected.get_metadata(0) as String
			if path.get_extension().to_lower() == "gdmappergraph":
				EditorInterface.set_main_screen_editor(PLUGIN_NAME)
				GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(path)
	)
	
	# second split
	var file_item_list = fs_dock.find_children("@FileSystemList*", "FileSystemList", true, false)[0]
	file_item_list.item_activated.connect(func(index):
		var path = file_item_list.get_item_metadata(index) as String
		if path.get_extension().to_lower() == "gdmappergraph":
			EditorInterface.set_main_screen_editor(PLUGIN_NAME)
			GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(path)
	)
	
func _on_file_system_dock_popup_menu_idex_pressed(index: int):
	var fs_dock = EditorInterface.get_file_system_dock()
	for i in fs_dock.get_children(true):
		if i is PopupMenu:
			for j in i.item_count:
				if i.get_item_text(j) in ["Open", tr("Open")]:
					if i.get_item_text(index) in ["Open", tr("Open")]:
						var path = EditorInterface.get_current_path()
						if path.get_extension().to_lower() == "gdmappergraph":
							EditorInterface.set_main_screen_editor(PLUGIN_NAME)
							GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(path)
							return
							
func set_up_localization():
	var domain = TranslationServer.get_or_add_domain("GDSQL")
	
	var translations = [
		load("res://addons/gdsql/translation/translation.de.translation"),
		load("res://addons/gdsql/translation/translation.en.translation"),
		load("res://addons/gdsql/translation/translation.es.translation"),
		load("res://addons/gdsql/translation/translation.fr.translation"),
		load("res://addons/gdsql/translation/translation.it.translation"),
		load("res://addons/gdsql/translation/translation.ja.translation"),
		load("res://addons/gdsql/translation/translation.ko.translation"),
		load("res://addons/gdsql/translation/translation.pl.translation"),
		load("res://addons/gdsql/translation/translation.pt_BR.translation"),
		load("res://addons/gdsql/translation/translation.ru.translation"),
		load("res://addons/gdsql/translation/translation.tr.translation"),
		load("res://addons/gdsql/translation/translation.zh_CN.translation"),
		load("res://addons/gdsql/translation/translation.zh_TW.translation"),
	]
	
	for translation in translations:
		domain.add_translation(translation)
		
func init_settings() -> Error:
	var settings_path = "res://gdsql/settings.cfg"
	var settings: ConfigFile
	if not FileAccess.file_exists(settings_path):
		if not DirAccess.dir_exists_absolute(settings_path.get_base_dir()):
			var err = DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
			if err != OK:
				push_error("Initialize GDSQL settings failed! Path: %s." % settings_path.get_base_dir())
				return FAILED
				
		settings = ConfigFile.new()
		settings.save(settings_path)
	else:
		settings = ConfigFile.new()
		settings.load(settings_path)
		
	var default_values = {
		"config/root_config_path": "res://gdsql/define/config.cfg",
		"config/database_dir": "res://gdsql/database",
	}
	
	var changed = false
	for prop: String in default_values:
		var section = prop.get_slice("/", 0)
		var key = prop.get_slice("/", 1)
		if not settings.has_section_key(section, key):
			settings.set_value(section, key, default_values[prop])
			changed = true
			
	if changed:
		settings.save(settings_path)
		
	if true:
		var path: String = settings.get_value("config", "root_config_path")
		if not FileAccess.file_exists(path):
			var err = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			if err == OK:
				var cf = ConfigFile.new()
				cf.save(path)
			else:
				push_error("Initialize GDSQL root config failed! Path: %s." % path)
				return FAILED
				
	if true:
		var path: String = settings.get_value("config", "database_dir")
		if not DirAccess.dir_exists_absolute(path):
			var err = DirAccess.make_dir_recursive_absolute(path)
			if err != OK:
				push_error("Initialize GDSQL database dir failed! Path: %s." % path)
				return FAILED
				
	return OK
