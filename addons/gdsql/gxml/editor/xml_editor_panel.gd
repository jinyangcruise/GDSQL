@tool
extends PanelContainer

@onready var file_menu: PopupMenu = $VBoxContainer/MenuBar/File
@onready var filter_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FilterFile
@onready var file_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer/FileTree
@onready var filter_name: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/FilterName
@onready var item_tree: Tree = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/ItemTree
@onready var xml_editor_container: Control = $VBoxContainer/HSplitContainer/XMLEditorContainer
@onready var curr_file: LineEdit = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/CurrFile
@onready var sort_button: TextureButton = $VBoxContainer/HSplitContainer/VSplitContainer/VBoxContainer2/HBoxContainer/SortButton

var editor_file_new_dialog = EditorFileDialog.new()
var editor_file_open_dialog = EditorFileDialog.new() 

enum FILE_MANU_OPTION {
	NEW = 0,
	OPEN = 1,
	SAVE = 3,
	SAVE_AS = 4,
	SAVE_ALL = 5,
	CLOSE = 7,
	CLOSE_ALL = 8,
	CLOSE_OTHER_TABS = 9
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
	
	file_menu.set_item_shortcut(FILE_MANU_OPTION.NEW, SHORTCUT_NEW)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.OPEN, SHORTCUT_OPEN)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE, SHORTCUT_SAVE)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE_AS, SHORTCUT_SAVEAS)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.SAVE_ALL, SHORTCUT_SAVEALL)
	file_menu.set_item_shortcut(FILE_MANU_OPTION.CLOSE, SHORTCUT_CLOSE)
	
	filter_file.right_icon = get_theme_icon("Search", "EditorIcons")
	filter_name.right_icon = get_theme_icon("Search", "EditorIcons")
	sort_button.texture_normal = get_theme_icon("Sort", "EditorIcons")
	sort_button.texture_pressed = get_theme_icon("YSort", "EditorIcons")
	
	_init_file_new_dialog()
	_init_file_open_dialog()

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
	curr_file.text = path.get_file()
	
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
			pass
		FILE_MANU_OPTION.SAVE_ALL:
			pass
		FILE_MANU_OPTION.CLOSE:
			pass
		FILE_MANU_OPTION.CLOSE_ALL:
			pass
		FILE_MANU_OPTION.CLOSE_OTHER_TABS:
			pass

func _save():
	var item = file_tree.get_selected()
	if not item:
		return
	if item.get_meta("editor") and item.get_meta("editor").text_editor:
		var file = FileAccess.open(item.get_meta("path"), FileAccess.WRITE)
		file.store_string(item.get_meta("editor").text_editor.text)
		file.flush()
		item.set_text(0, item.get_text(0).replace("(*)", ""))
		curr_file.text = item.get_text(0)
		
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
	
func _on_file_tree_item_selected() -> void:
	var item = file_tree.get_selected()
	if not item:
		return
	var xml_editor = item.get_meta("editor")
	for i in xml_editor_container.get_children():
		if i == xml_editor:
			i.show()
		else:
			i.hide()
