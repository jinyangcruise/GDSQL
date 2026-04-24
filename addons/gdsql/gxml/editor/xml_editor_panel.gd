@tool
extends PanelContainer

@onready var file_menu: PopupMenu = $VBoxContainer/HBoxContainer/MenuBar/File
@onready var search_menu: PopupMenu = $VBoxContainer/HBoxContainer/MenuBar/Search
@onready var filter_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FilterFile
@onready var file_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FileTree
@onready var filter_name: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/FilterName
@onready var item_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/ItemTree
@onready var xml_editor_container: PanelContainer = $VBoxContainer/HSplitContainer/VBoxContainer/XMLEditorContainer
@onready var find_replace_bar: HBoxContainer = $VBoxContainer/HSplitContainer/VBoxContainer/FindReplaceBar
@onready var curr_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/CurrFile
@onready var sort_button: TextureButton = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/SortButton
@onready var rmb_menu: PopupMenu = $RMBMenu
@onready var left_window: VSplitContainer = $VBoxContainer/HSplitContainer/VSplitContainer
@onready var pin_to_top_button: Button = $VBoxContainer/HBoxContainer/HBoxContainer/PinToTopButton
@onready var debug_menu: PopupMenu = $VBoxContainer/HBoxContainer/MenuBar/Debug

var editor_file_new_dialog = EditorFileDialog.new()
var editor_file_open_dialog = EditorFileDialog.new()
var editor_file_saveas_dialog = EditorFileDialog.new()
var confirm_save_dialog = ConfirmationDialog.new()
var file_not_exist_dialog = AcceptDialog.new()
var search_help_dialog = preload("res://addons/gdsql/gxml/editor/search_herlp.tscn").instantiate()

var history = []
var closing_item: TreeItem # 正在关闭的tab
var sub_menu: PopupMenu
var zoom_factor: float = 1.0

const config_path = "user://xml_editor.cfg"
var config: ConfigFile

enum FILE_MANU_OPTION {
	NEW = 0,
	OPEN = 1,
	OPEN_RECENT = 2,
	SAVE = 4,
	SAVE_AS = 5,
	SAVE_ALL = 6,
	CLOSE = 8,
	CLOSE_ALL = 9,
	CLOSE_OTHER_TABS = 10
}

enum RMB_MENU_OPTION {
	SAVE = 0,
	SAVE_AS = 1,
	CLOSE = 3,
	CLOSE_ALL = 4,
	CLOSE_OTHER_TABS = 5,
	SOFT_RELOAD_TOOL_SCRIPT = 7,
	SHOW_IN_FILE_SYSTEM = 9,
}

enum SEARCH_MENU_OPTION {
	FIND = 0,
	FIND_NEXT = 1,
	FIND_PREVIOUS = 2,
	REPLACE = 3,
	FIND_IN_FILES = 5,
	REPLACE_IN_FILES = 6,
	CONTEXTUAL_HELP = 8,
}

const SHORTCUT_NEW = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_new.tres")
const SHORTCUT_OPEN = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_open.tres")
const SHORTCUT_SAVE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_save.tres")
const SHORTCUT_SAVEAS = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_saveas.tres")
const SHORTCUT_SAVEALL = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_saveall.tres")
const SHORTCUT_CLOSE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_close.tres")
const SHORTCUT_CONTEXTUALHELP = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_contextualhelp.tres")
const SHORTCUT_FIND = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_find.tres")
const SHORTCUT_FINDINFILES = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_findinfiles.tres")
const SHORTCUT_FINDNEXT = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_findnext.tres")
const SHORTCUT_FINDPREVIOUS = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_findprevious.tres")
const SHORTCUT_REPLACE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_replace.tres")
const SHORTCUT_REPLACEINFILES = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_replaceinfiles.tres")

const NEW_MAPPER_CONTENT = """
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE mapper
PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
"http://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="TestSkillMapper">
	<cache/>
	
</mapper> 
"""



func _ready() -> void:
	set_translation_domain("godot.editor")
	add_theme_stylebox_override(&"panel", get_theme_stylebox(&"PanelForeground", &"EditorStyles"))
	file_tree.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"ItemList"))
	file_tree.create_item()
	file_tree.hide_root = true
	
	item_tree.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"ItemList"))
	item_tree.create_item()
	item_tree.hide_root = true
	item_tree.set_column_expand(1, true)
	item_tree.set_column_expand_ratio(1, 2)
	
	file_menu.set_item_shortcut(FILE_MANU_OPTION.NEW, SHORTCUT_NEW)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.OPEN, SHORTCUT_OPEN)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE, SHORTCUT_SAVE)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE_AS, SHORTCUT_SAVEAS)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE_ALL, SHORTCUT_SAVEALL)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.CLOSE, SHORTCUT_CLOSE)
	
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.FIND, SHORTCUT_FIND)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.FIND_NEXT, SHORTCUT_FINDNEXT)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.FIND_PREVIOUS, SHORTCUT_FINDPREVIOUS)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.REPLACE, SHORTCUT_REPLACE)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.FIND_IN_FILES, SHORTCUT_FINDINFILES)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.REPLACE_IN_FILES, SHORTCUT_REPLACEINFILES)
	search_menu.set_item_shortcut(SEARCH_MENU_OPTION.CONTEXTUAL_HELP, SHORTCUT_CONTEXTUALHELP)
	
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.SAVE, SHORTCUT_SAVE)
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.SAVE_AS, SHORTCUT_SAVEAS)
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.CLOSE, SHORTCUT_CLOSE)
	
	_deal_popup_menu_hide_behind_window_bug()
	
	xml_editor_container.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"ScriptEditor", &"EditorStyles"))
	
	config = ConfigFile.new()
	config.load(config_path)
	
	sub_menu = PopupMenu.new()
	sub_menu.index_pressed.connect(_on_sub_menu_index_pressed)
	refresh_sub_menu()
	file_menu.set_item_submenu_node(FILE_MANU_OPTION.OPEN_RECENT, sub_menu)
	
	filter_file.right_icon = get_theme_icon("Search", "EditorIcons")
	filter_name.right_icon = get_theme_icon("Search", "EditorIcons")
	sort_button.texture_normal = get_theme_icon("Sort", "EditorIcons")
	sort_button.texture_pressed = get_theme_icon("YSort", "EditorIcons")
	pin_to_top_button.icon = get_theme_icon("Pin", "EditorIcons")
	
	_init_file_new_dialog()
	_init_file_open_dialog()
	_init_confirm_save_dialog()
	_init_file_not_exist_dialog()
	_init_file_saveas_dialog()
	_init_search_help_dialog()
	
	bind_file_system_events()
	
	var unclosed_files = config.get_value("history", "unclosed", [])
	config.set_value("history", "unclosed", [])
	for path in unclosed_files:
		if FileAccess.file_exists(path):
			open_file(path)
		else:
			print_rich("[color=yellow]XML Editor: File not exist, '%s'[/color]" % path)
			
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if file_tree:
			file_tree.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"ItemList"))
		if item_tree:
			item_tree.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"ItemList"))
		if xml_editor_container:
			xml_editor_container.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"ScriptEditor", &"EditorStyles"))
			
func refresh_sub_menu():
	var recent_files = config.get_value("history", "primary", [])
	sub_menu.clear()
	for i in recent_files:
		sub_menu.add_item(i)
	sub_menu.add_separator()
	sub_menu.add_item(tr("Clear Recent Files"))
	if recent_files.is_empty():
		sub_menu.set_item_disabled(sub_menu.get_child_count()-1, true)
		
func remove_from_recent_history(path: String):
	var recent_files = config.get_value("history", "primary", []) as Array
	if recent_files.has(path):
		recent_files.erase(path)
		config.set_value("history", "primary", recent_files)
		config.save(config_path)
		
func clear_recent_history():
	config.set_value("history", "primary", [])
	config.save(config_path)
	
func add_to_recent_history(path: String):
	var recent_files = config.get_value("history", "primary", []) as Array
	if recent_files.has(path):
		recent_files.erase(path)
	recent_files.push_front(path)
	config.set_value("history", "primary", recent_files)
	config.save(config_path)
	
func remove_from_unclosed_files(path: String):
	var unclosed_files = config.get_value("history", "unclosed", []) as Array
	unclosed_files.erase(path)
	config.set_value("history", "unclosed", unclosed_files)
	config.save(config_path)
	refresh_sub_menu()
	
func clear_unclosed_files():
	config.set_value("history", "unclosed", [])
	config.save(config_path)
	refresh_sub_menu()
	
func add_to_unclosed_files(path: String):
	var unclosed_files = config.get_value("history", "unclosed", []) as Array
	unclosed_files.push_back(path)
	config.set_value("history", "unclosed", unclosed_files)
	config.save(config_path)
	refresh_sub_menu()
	
func modify_item_name(item: TreeItem):
	var path = item.get_meta("path")
	var arr_name = {}
	for i: TreeItem in file_tree.get_root().get_children():
		arr_name[i.get_text(0)] = i
		
	var a_name = path.get_file()
	if arr_name.has(a_name):
		arr_name[a_name].set_text(0, arr_name[a_name].get_meta("path"))
		a_name = path
	item.set_text(0, a_name)
	
func open_file(path: String, p_line: int = 0, p_begin: int = -1, p_end: int = -1):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	var arr_name = {}
	for i: TreeItem in file_tree.get_root().get_children():
		arr_name[i.get_text(0)] = i
		if i.get_meta("path") == path:
			i.select(0)
			var a_xml_editor = i.get_meta("editor")
			if p_begin != -1 and p_end != -1:
				a_xml_editor.call_deferred("goto_line_selection", p_line, p_begin, p_end)
			elif p_line != -1:
				a_xml_editor.call_deferred("goto_line", p_line, 0)
			return
			
	var file_tree_item = file_tree.create_item(file_tree.get_root())
	var a_name = path.get_file()
	if arr_name.has(a_name):
		arr_name[a_name].set_text(0, arr_name[a_name].get_meta("path"))
		a_name = path
	file_tree_item.set_text(0, a_name)
	file_tree_item.set_icon_max_width(0, get_theme_icon("TextFile", "EditorIcons").get_width())
	file_tree_item.set_icon(0, load("res://addons/gdsql/gbatis/img/xml.svg"))
	
	# new 
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error(error_string(FileAccess.get_open_error()))
	var content = file.get_as_text()
	var xml_editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
	xml_editor.content = content
	xml_editor_container.add_child(xml_editor)
	xml_editor.text_changed.connect(_on_text_changed)
	xml_editor.toggle_scripts_pressed.connect(toggle_left_window)
	xml_editor.zoomed.connect(_update_zoom)
	xml_editor.call_deferred("set_zoom_factor", zoom_factor)
	
	if p_begin != -1 and p_end != -1:
		xml_editor.call_deferred("goto_line_selection", p_line, p_begin, p_end)
	elif p_line != -1:
		xml_editor.call_deferred("goto_line", p_line, 0)
		
	file_tree_item.set_meta("path", path)
	file_tree_item.set_meta("editor", xml_editor)
	file_tree_item.select(0)
	if filter_file.text != "":
		file_tree_item.visible = file_tree_item.get_text(0).contains(filter_file.text)
	remove_from_recent_history(path)
	add_to_unclosed_files(path)
	
func toggle_left_window():
	left_window.visible = not left_window.visible
	for item: TreeItem in history:
		item.get_meta("editor").scripts_panel_toggled = not left_window.visible
		
func refresh_xml_item_tree():
	item_tree.clear()
	var root = item_tree.create_item()
	if history.is_empty():
		return
	var item = history.back() as TreeItem
	var gxml = ResourceLoader.load(item.get_meta("path"), "", ResourceLoader.CACHE_MODE_IGNORE)
	if not gxml or not gxml.root_item:
		print_rich("[color=yellow]This file %s is not a xml.[/color]" % item.get_meta("path"))
		return
	for i in gxml.root_item.content:
		parse_gxml_item(i, root, item_tree)
		
func parse_gxml_item(item: GDSQL.GXMLItem, parent_tree_item: TreeItem, tree: Tree):
	var tree_item = tree.create_item(parent_tree_item)
	tree_item.set_meta("line", item.line)
	var id = ""
	for i in item.attrs:
		if i == "id":
			id = item.attrs[i]
			
	tree_item.set_text(0, item.name)
	if id != "":
		tree_item.set_text(1, id)
		
	if filter_name.text != "":
		tree_item.visible = item.name.contains(filter_name.text) or id.contains(filter_name.text)
		
func _on_text_changed():
	var item = file_tree.get_selected()
	if not item:
		return
	if not item.get_text(0).ends_with("(*)"):
		item.set_text(0, item.get_text(0) + "(*)")
		curr_file.text = item.get_text(0)
		
func _on_file_menu_id_pressed(id: int) -> void:
	_recover_on_top()
	match id:
		FILE_MANU_OPTION.NEW:
			editor_file_new_dialog.popup_centered_ratio(0.5)
		FILE_MANU_OPTION.OPEN:
			editor_file_open_dialog.popup_centered_ratio(0.5)
		FILE_MANU_OPTION.SAVE:
			_save()
		FILE_MANU_OPTION.SAVE_AS:
			editor_file_saveas_dialog.popup_centered_ratio(0.5)
		FILE_MANU_OPTION.SAVE_ALL:
			_save_all()
		FILE_MANU_OPTION.CLOSE:
			await _close()
		FILE_MANU_OPTION.CLOSE_ALL:
			await _close_all()
		FILE_MANU_OPTION.CLOSE_OTHER_TABS:
			await _close_other_tabs()
			
func _on_rmb_menu_index_pressed(index: int) -> void:
	_recover_on_top()
	var item = rmb_menu.get_meta("item")
	rmb_menu.remove_meta("item")
	match index:
		RMB_MENU_OPTION.SAVE:
			_save()
		RMB_MENU_OPTION.SAVE_AS:
			editor_file_saveas_dialog.popup_centered_ratio(0.5)
		RMB_MENU_OPTION.CLOSE:
			await _close()
		RMB_MENU_OPTION.CLOSE_ALL:
			await _close_all()
		RMB_MENU_OPTION.CLOSE_OTHER_TABS:
			await _close_other_tabs()
		RMB_MENU_OPTION.SOFT_RELOAD_TOOL_SCRIPT:
			_reload_script_editor(item)
		RMB_MENU_OPTION.SHOW_IN_FILE_SYSTEM:
			if item.get_meta("path").begins_with("res://"):
				EditorInterface.get_file_system_dock().navigate_to_path(item.get_meta("path"))
			else:
				OS.shell_show_in_file_manager(item.get_meta("path"), true)
				
func _on_sub_menu_index_pressed(index: int) -> void:
	_recover_on_top()
	if index == sub_menu.get_child_count() - 1:
		for i in index:
			sub_menu.remove_item(i)
		clear_recent_history()
		return
		
	var path = sub_menu.get_item_text(index)
	if not FileAccess.file_exists(path):
		remove_from_recent_history(path)
		file_not_exist_dialog.popup_centered()
		return
		
	open_file(path)
	
func _save():
	if not history.is_empty():
		_save_file(history.back())
		
func _save_file(item: TreeItem):
	if not item.get_meta("editor") or not item.get_meta("editor").text_editor or\
	not item.get_text(0).ends_with("(*)"):
		return
		
	var path = item.get_meta("path")
	var content = item.get_meta("editor").text_editor.text
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.flush()
	file = null
	item.set_text(0, item.get_text(0).replace("(*)", ""))
	curr_file.text = item.get_text(0)
	refresh_xml_item_tree()
	var res = load(item.get_meta("path"))
	if EditorInterface.get_inspector().get_edited_object() == res:
		res.notify_property_list_changed()
		
func _save_all():
	for item in file_tree.get_root().get_children():
		_save_file(item)
		
func _close():
	if history.is_empty():
		return
	var item = history.back()
	closing_item = item
	if item.get_text(0).ends_with("(*)"):
		confirm_save_dialog.popup_centered()
		return
	_close_tab(false)
	if history.is_empty():
		curr_file.text = ""
		
func _close_all():
	var items = []
	for i in history:
		items.push_front(i)
	for item in items:
		closing_item = item
		if item.get_text(0).ends_with("(*)"):
			confirm_save_dialog.popup_centered()
			await confirm_save_dialog.visibility_changed
			if confirm_save_dialog.visible:
				await confirm_save_dialog.visibility_changed
			await get_tree().create_timer(0.1).timeout
		else:
			_close_tab(false)
			
	if history.is_empty():
		curr_file.text = ""
		
func _close_other_tabs():
	if history.is_empty():
		return
	var curr_tab = history.back()
	for item: TreeItem in file_tree.get_root().get_children():
		if item == curr_tab:
			continue
		closing_item = item
		if item.get_text(0).ends_with("(*)"):
			confirm_save_dialog.popup_centered()
			await confirm_save_dialog.visibility_changed
			if confirm_save_dialog.visible:
				await confirm_save_dialog.visibility_changed
		else:
			_close_tab(false)
			
func _init_file_new_dialog():
	editor_file_new_dialog.filters = PackedStringArray(["*.xml"])
	editor_file_new_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	editor_file_new_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_new_dialog.file_selected.connect(func(path: String):
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(NEW_MAPPER_CONTENT)
		file.flush()
		file = null
		# scan后窗口可能被最小化了，保持置顶
		var old_always_on_top = pin_to_top_button.button_pressed
		if not old_always_on_top:
			_on_pin_to_top_button_toggled(true)
		EditorInterface.get_resource_filesystem().scan()
		open_file(path)
		if not old_always_on_top:
			await get_tree().create_timer(1).timeout
			_on_pin_to_top_button_toggled(false)
	, CONNECT_DEFERRED)
	add_child(editor_file_new_dialog)
	editor_file_new_dialog.hide()
	# fix bug of godot
	editor_file_new_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(editor_file_new_dialog))
	
func _init_file_open_dialog():
	editor_file_open_dialog.filters = PackedStringArray(["*.xml"])
	editor_file_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	editor_file_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_open_dialog.file_selected.connect(func(path: String):
		open_file(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_open_dialog)
	editor_file_open_dialog.hide()
	# fix bug of godot
	editor_file_open_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(editor_file_open_dialog))
	
func _init_file_saveas_dialog():
	editor_file_saveas_dialog.filters = PackedStringArray(["*.xml"])
	editor_file_saveas_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	editor_file_saveas_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_saveas_dialog.file_selected.connect(func(path: String):
		var content = ""
		for i in xml_editor_container.get_children():
			if i.visible:
				content = i.text_editor.text
				break
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(content)
		file.flush()
		file = null
		EditorInterface.get_resource_filesystem().scan()
		# scan后窗口可能被最小化了，所以用窗口的方法，能重新激活
		while EditorInterface.get_resource_filesystem().is_scanning():
			await get_tree().process_frame
		get_window().open_file(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_saveas_dialog)
	editor_file_saveas_dialog.hide()
	# fix bug of godot
	editor_file_saveas_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(editor_file_saveas_dialog))
	
func _init_confirm_save_dialog():
	confirm_save_dialog.ok_button_text = tr("Save")
	confirm_save_dialog.add_button(tr("Discard"), DisplayServer.get_swap_cancel_ok(), "discard")
	confirm_save_dialog.confirmed.connect(_close_tab.bind(true))
	confirm_save_dialog.custom_action.connect(_discard)
	confirm_save_dialog.about_to_popup.connect(func():
		confirm_save_dialog.dialog_text = tr("Close and save changes?") + \
			"\n\"" + closing_item.get_meta("path") + "\""
	)
	add_child(confirm_save_dialog)
	confirm_save_dialog.hide()
	# fix bug of godot
	confirm_save_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(confirm_save_dialog))
	
func _init_file_not_exist_dialog():
	file_not_exist_dialog.dialog_text = tr("File does not exist.")
	add_child(file_not_exist_dialog)
	file_not_exist_dialog.hide()
	# fix bug of godot
	file_not_exist_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(file_not_exist_dialog))
		
func _init_search_help_dialog():
	add_child(search_help_dialog)
	search_help_dialog.hide()
	search_help_dialog.visibility_changed.connect(
		_on_dialog_visibility_changed.bind(search_help_dialog))
	search_help_dialog.search_help_insert.connect(_on_search_help_insert)
	
func _on_search_help_insert(content: String):
	if history.is_empty():
		return
	var editor = history.back().get_meta("editor").text_editor as CodeEdit
	editor.insert_text_at_caret(content, 0)
	
func _reload_script_editor(item: TreeItem):
	var old_editor = item.get_meta("editor") as Node
	var content = old_editor.text_editor.text
	var xml_editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
	xml_editor.content = content
	xml_editor.text_changed.connect(_on_text_changed)
	xml_editor.toggle_scripts_pressed.connect(toggle_left_window)
	xml_editor.zoomed.connect(_update_zoom)
	xml_editor.call_deferred("set_zoom_factor", zoom_factor)
	xml_editor.scripts_panel_toggled = not left_window.visible
	var scroll_value = (old_editor.text_editor as CodeEdit).get_v_scroll_bar().value
	item.remove_meta("editor")
	item.set_meta("editor", xml_editor)
	xml_editor_container.add_child(xml_editor)
	xml_editor_container.remove_child(old_editor)
	xml_editor.visible = old_editor.visible
	old_editor.queue_free()
	await get_tree().create_timer(0.1).timeout
	(xml_editor.text_editor as CodeEdit).get_v_scroll_bar().value = scroll_value
	
func _update_zoom(p_zoom_factor: float):
	zoom_factor = p_zoom_factor
	for i in history:
		var editor = i.get_meta("editor")
		editor.set_zoom_factor(p_zoom_factor)
		
func _close_tab(p_save: bool):
	var item = closing_item
	var path = item.get_meta("path")
	closing_item = null
	if p_save:
		_save_file(item)
	history.erase(item)
	var editor = item.get_meta("editor")
	if history.is_empty():
		item.get_parent().remove_child(item)
		xml_editor_container.remove_child(editor)
	else:
		var last = history.back()
		open_file(last.get_meta("path"))
	item.free()
	editor.queue_free()
	add_to_recent_history(path)
	remove_from_unclosed_files(path)
	_update_find_replace_bar()
	if history.is_empty():
		refresh_xml_item_tree()
		
func _discard(_action: String):
	_close_tab(false)
	confirm_save_dialog.hide()
	
func _update_find_replace_bar():
	if history.is_empty():
		find_replace_bar.set_text_edit(null)
		find_replace_bar.hide()
	else:
		history.back().get_meta("editor").set_find_replace_bar(find_replace_bar)
		
func _on_file_tree_item_selected() -> void:
	var item = file_tree.get_selected()
	if not item:
		return
	history.erase(item)
	history.push_back(item)
	var xml_editor = item.get_meta("editor")
	curr_file.text = item.get_text(0)
	for i: Node in xml_editor_container.get_children():
		if i == xml_editor:
			i.show()
			i.set_process(true)
			_update_find_replace_bar()
		else:
			i.hide()
			i.set_process(false)
	refresh_xml_item_tree()
	
func _on_file_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var item = file_tree.get_item_at_position(file_tree.get_local_mouse_position())
		if not item:
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.is_pressed():
			closing_item = item
			if item.get_text(0).ends_with("(*)"):
				confirm_save_dialog.popup_centered()
				return
			_close_tab(false)
			if history.is_empty():
				curr_file.text = ""
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			rmb_menu.position = DisplayServer.mouse_get_position()
			rmb_menu.popup()
			rmb_menu.set_meta("item", item)
			
func _on_debug_index_pressed(index: int) -> void:
	_recover_on_top()
	if history.is_empty():
		return
	var item = history.back() as TreeItem
	match index:
		0:
			var path = item.get_meta("path")
			var gxml = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var validator = GDSQL.GBatisMapperValidator.new()
			var ret = validator.validate(gxml)
			if ret:
				EditorInterface.get_editor_toaster().push_toast("No error found.", EditorToaster.SEVERITY_WARNING)
			else:
				EditorInterface.get_editor_toaster().push_toast("Error!", EditorToaster.SEVERITY_ERROR)
				
func _on_filter_file_text_changed(new_text: String) -> void:
	for item: TreeItem in history:
		if new_text == "":
			item.visible = true
		else:
			new_text = new_text.replace("_", "").to_lower()
			item.visible = item.get_text(0).replace("_", "").to_lower().contains(new_text)
			
func _on_filter_name_text_changed(new_text: String) -> void:
	for item: TreeItem in item_tree.get_root().get_children():
		if new_text == "":
			item.visible = true
		else:
			new_text = new_text.replace("_", "").to_lower()
			if item.get_text(0).replace("_", "").to_lower().contains(new_text) or \
			item.get_text(1).replace("_", "").to_lower().contains(new_text):
				item.visible = true
			else:
				item.visible = false
	if new_text == "":
		item_tree.scroll_to_item(item_tree.get_selected(), true)
		
func _on_item_tree_item_selected() -> void:
	var item = item_tree.get_selected()
	var line = item.get_meta("line")
	var editor = history.back().get_meta("editor")
	(editor.text_editor as CodeEdit).set_caret_line(line)
	(editor.text_editor as CodeEdit).center_viewport_to_caret(0)
	(editor.text_editor as CodeEdit).select_word_under_caret(0)
	for aitem: TreeItem in item_tree.get_root().get_children():
		if aitem != item:
			aitem.deselect(0)
			
func _on_search_index_pressed(index: int) -> void:
	match index:
		SEARCH_MENU_OPTION.FIND:
			if not history.is_empty():
				find_replace_bar.popup_search()
		SEARCH_MENU_OPTION.FIND_NEXT:
			if not history.is_empty():
				find_replace_bar.search_next()
		SEARCH_MENU_OPTION.FIND_PREVIOUS:
			if not history.is_empty():
				find_replace_bar.search_prev()
		SEARCH_MENU_OPTION.REPLACE:
			if not history.is_empty():
				find_replace_bar.popup_replace()
		SEARCH_MENU_OPTION.FIND_IN_FILES:
			pass
			# TODO script_text_editor.cpp 1500
		SEARCH_MENU_OPTION.REPLACE_IN_FILES:
			pass
		SEARCH_MENU_OPTION.CONTEXTUAL_HELP:
			var search = ""
			if not history.is_empty():
				search = (history.back().get_meta("editor").text_editor as CodeEdit).get_selected_text(0)
			search_help_dialog.popup_search(search)
			
func _on_pin_to_top_button_toggled(toggled_on: bool) -> void:
	get_window().transient = false
	get_window().always_on_top = toggled_on
	
func bind_file_system_events():
	var dock = EditorInterface.get_file_system_dock()
	dock.file_removed.connect(_on_file_removed)
	dock.files_moved.connect(_on_file_moved)
	dock.folder_removed.connect(_on_folder_removed)
	dock.folder_moved.connect(_on_folder_moved)
	
func unbind_file_system_events():
	var dock = EditorInterface.get_file_system_dock()
	dock.file_removed.disconnect(_on_file_removed)
	dock.files_moved.disconnect(_on_file_moved)
	dock.folder_removed.disconnect(_on_folder_removed)
	dock.folder_moved.disconnect(_on_folder_moved)
	
func _on_file_removed(path: String):
	for item in history:
		if item.get_meta("path") == path:
			closing_item = item
			_close_tab(false)
			break
			
func _on_file_moved(old_file: String, new_file: String):
	for item in history:
		if item.get_meta("path") == old_file:
			item.set_meta("path", new_file)
			modify_item_name(item)
			break
			
func _on_folder_removed(folder: String):
	for item in history:
		if item.get_meta("path").begins_with(folder):
			closing_item = item
			_close_tab(false)
			break
			
func _on_folder_moved(old_folder: String, new_folder: String):
	for item in history:
		if item.get_meta("path").begins_with(old_folder):
			item.set_meta("path", item.get_meta("path").replace(old_folder, new_folder))
			modify_item_name(item)
			
# INFO 由于godot的bug，导致always on top的主窗口的popupmenu被挡住了。所以临时取消置顶。
# 但该方法仍旧不能彻底解决问题，当popupmenu的选项激活了另一个窗口时，主窗口的always on top仍不生效。
func _deal_popup_menu_hide_behind_window_bug():
	file_menu.about_to_popup.connect(_on_popup_menu_about_to_popup)
	debug_menu.about_to_popup.connect(_on_popup_menu_about_to_popup)
	search_menu.about_to_popup.connect(_on_popup_menu_about_to_popup)
	rmb_menu.about_to_popup.connect(_on_popup_menu_about_to_popup)
	
	file_menu.visibility_changed.connect(_on_popup_menu_visibility_changed.bind(file_menu))
	debug_menu.visibility_changed.connect(_on_popup_menu_visibility_changed.bind(debug_menu))
	search_menu.visibility_changed.connect(_on_popup_menu_visibility_changed.bind(search_menu))
	rmb_menu.visibility_changed.connect(_on_popup_menu_visibility_changed.bind(rmb_menu))
	
func _on_popup_menu_about_to_popup():
	if pin_to_top_button.button_pressed:
		_on_pin_to_top_button_toggled(false)
		pin_to_top_button.set_meta("need_recover", true)
		
func _on_popup_menu_visibility_changed(menu: PopupMenu):
	if not menu.visible:
		_recover_on_top()
		
func _recover_on_top():
	if pin_to_top_button.has_meta("need_recover"):
		_on_pin_to_top_button_toggled(true)
		pin_to_top_button.remove_meta("need_recover")
		
func _on_dialog_visibility_changed(dialog: AcceptDialog):
	if dialog.visible == false:
		# INFO dialog关闭的时候，要重置一下window的置顶信息，否则置顶失败
		if pin_to_top_button.button_pressed:
			_on_pin_to_top_button_toggled(false)
			_on_pin_to_top_button_toggled(true)
