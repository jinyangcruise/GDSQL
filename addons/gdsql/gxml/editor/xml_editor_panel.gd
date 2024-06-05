@tool
extends PanelContainer
# TODO FIXME WAIT_FOR_UPDATE 4.3.dev6存在一个问题，window重新打开后，打字区域丢失光标或者是没有闪烁，
# 在4.3 beta1中，问题似乎得到修改。所以后续更新版本后进行验证。

@onready var file_menu: PopupMenu = $VBoxContainer/MenuBar/File
@onready var filter_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FilterFile
@onready var file_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FileTree
@onready var filter_name: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/FilterName
@onready var item_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/ItemTree
@onready var xml_editor_container: Control = $VBoxContainer/HSplitContainer/XMLEditorContainer
@onready var curr_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/CurrFile
@onready var sort_button: TextureButton = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/SortButton
@onready var rmb_menu: PopupMenu = $RMBMenu

var editor_file_new_dialog = EditorFileDialog.new()
var editor_file_open_dialog = EditorFileDialog.new()
var editor_file_saveas_dialog = EditorFileDialog.new()
var confirm_save_dialog = ConfirmationDialog.new()
var file_not_exist_dialog = AcceptDialog.new()

var history = []
var closing_item: TreeItem # 正在关闭的tab
var sub_menu: PopupMenu

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
}

const SHORTCUT_NEW = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_new.tres")
const SHORTCUT_OPEN = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_open.tres")
const SHORTCUT_SAVE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_save.tres")
const SHORTCUT_SAVEAS = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_saveas.tres")
const SHORTCUT_SAVEALL = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_saveall.tres")
const SHORTCUT_CLOSE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_close.tres")

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
	file_tree.create_item()
	file_tree.hide_root = true
	
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
	
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.SAVE, SHORTCUT_SAVE)
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.SAVE_AS, SHORTCUT_SAVEAS)
	rmb_menu.set_item_shortcut(RMB_MENU_OPTION.CLOSE, SHORTCUT_CLOSE)
	
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
	
	_init_file_new_dialog()
	_init_file_open_dialog()
	_init_confirm_save_dialog()
	_init_file_not_exist_dialog()
	
	var unclosed_files = config.get_value("history", "unclosed", [])
	config.set_value("history", "unclosed", [])
	for path in unclosed_files:
		if FileAccess.file_exists(path):
			open_file(path)
		else:
			print_rich("[color=yellow]XML Editor: File not exist, '%s'[/color]" % path)
			
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
	
func open_file(path: String):
	var arr_name = {}
	for i: TreeItem in file_tree.get_root().get_children():
		arr_name[i.get_text(0)] = i
		if i.get_meta("path") == path or ProjectSettings.globalize_path(path) == path:
			i.select(0)
			return
			
	var file_tree_item = file_tree.create_item(file_tree.get_root())
	var a_name = path.get_file()
	if arr_name.has(a_name):
		arr_name[a_name].set_text(0, arr_name[a_name].get_meta("path"))
		a_name = path
	file_tree_item.set_text(0, a_name)
	file_tree_item.set_icon(0, get_theme_icon("TextFile", "EditorIcons"))
	
	# new 
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error(error_string(FileAccess.get_open_error()))
	var content = file.get_as_text()
	var xml_editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
	xml_editor.content = content
	xml_editor_container.add_child(xml_editor)
	xml_editor.text_changed.connect(_on_text_changed)
	
	file_tree_item.set_meta("path", path)
	file_tree_item.set_meta("editor", xml_editor)
	file_tree_item.select(0)
	if filter_file.text != "":
		file_tree_item.visible = file_tree_item.get_text(0).contains(filter_file.text)
	remove_from_recent_history(path)
	add_to_unclosed_files(path)
	
func refresh_xml_item_tree():
	item_tree.clear()
	var root = item_tree.create_item()
	if history.is_empty():
		return
	var item = history.back() as TreeItem
	var gxml = ResourceLoader.load(item.get_meta("path"), "", ResourceLoader.CACHE_MODE_IGNORE)
	if not gxml or not gxml.root_item:
		return
	for i in gxml.root_item.content:
		parse_gxml_item(i, root, item_tree)
		
func parse_gxml_item(item: GXMLItem, parent_tree_item: TreeItem, tree: Tree):
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
			
func _on_sub_menu_index_pressed(index: int) -> void:
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
	item.set_text(0, item.get_text(0).replace("(*)", ""))
	curr_file.text = item.get_text(0)
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
		EditorInterface.get_resource_filesystem().scan()
		open_file(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_new_dialog)
	editor_file_new_dialog.hide()
	
func _init_file_open_dialog():
	editor_file_open_dialog.filters = PackedStringArray(["*.xml"])
	editor_file_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	editor_file_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_open_dialog.file_selected.connect(func(path: String):
		open_file(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_open_dialog)
	editor_file_open_dialog.hide()
	
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
		open_file(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_saveas_dialog)
	editor_file_saveas_dialog.hide()
	
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
	
func _init_file_not_exist_dialog():
	file_not_exist_dialog.dialog_text = tr("file_not_exist_dialog.")
	add_child(file_not_exist_dialog)
	file_not_exist_dialog.hide()
	
func _reload_script_editor(item: TreeItem):
	var old_editor = item.get_meta("editor") as Node
	var content = old_editor.text_editor.text
	var xml_editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
	xml_editor.content = content
	xml_editor.text_changed.connect(_on_text_changed)
	var scroll_value = (old_editor.text_editor as CodeEdit).get_v_scroll_bar().value
	item.remove_meta("editor")
	item.set_meta("editor", xml_editor)
	xml_editor_container.add_child(xml_editor)
	xml_editor_container.remove_child(old_editor)
	xml_editor.visible = old_editor.visible
	old_editor.queue_free()
	await get_tree().create_timer(0.1).timeout
	(xml_editor.text_editor as CodeEdit).get_v_scroll_bar().value = scroll_value
	
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
	
func _discard(_action: String):
	_close_tab(false)
	confirm_save_dialog.hide()
	
func _on_file_tree_item_selected() -> void:
	var item = file_tree.get_selected()
	if not item:
		return
	history.erase(item)
	history.push_back(item)
	var xml_editor = item.get_meta("editor")
	curr_file.text = item.get_text(0)
	for i in xml_editor_container.get_children():
		if i == xml_editor:
			i.show()
		else:
			i.hide()
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
	if history.is_empty():
		return
	var item = history.back() as TreeItem
	match index:
		0:
			var path = item.get_meta("path")
			var gxml = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var validator = GBatisMapperValidator.new()
			var ret = validator.validate(gxml)
			if ret:
				printt("Success!")
			else:
				printt("Error!")
				
func _on_filter_file_text_changed(new_text: String) -> void:
	for item: TreeItem in history:
		if new_text == "":
			item.visible = true
		else:
			item.visible = item.get_text(0).contains(new_text)
			
func _on_filter_name_text_changed(new_text: String) -> void:
	for item: TreeItem in item_tree.get_root().get_children():
		if new_text == "":
			item.visible = true
		else:
			item.visible = item.get_text(0).contains(new_text)
			
func _on_item_tree_item_selected() -> void:
	var item = item_tree.get_selected()
	var line = item.get_meta("line")
	var editor = history.back().get_meta("editor")
	(editor.text_editor as CodeEdit).set_caret_line(line)
	(editor.text_editor as CodeEdit).center_viewport_to_caret(0)
