@tool
extends Window

@onready var xml_editor_panel: PanelContainer = $XMLEditorPanel

var inited = false

var file_tree: Tree
var file_item_list: ItemList

func _ready() -> void:
	set_translation_domain("godot.editor")
	transient = false
	bind_file_system_dock_popup_menu()
	
func _exit_tree() -> void:
	if file_tree:
		file_tree.item_activated.disconnect(_on_file_tree_item_activated)
	file_tree = null
	if file_item_list:
		file_item_list.item_activated.disconnect(_on_file_item_list_item_activated)
	file_item_list = null
	
func bind_file_system_dock_popup_menu():
	var fs_dock = EditorInterface.get_file_system_dock()
	# popup_menu
	for i in fs_dock.get_children(true):
		if i is PopupMenu:
			i.index_pressed.connect(_on_file_system_dock_popup_menu_idex_pressed)
			
	# double click
	# 可能激活了拆分模式
	var sc = fs_dock.find_child("@SplitContainer*", false, false)
	if not sc:
		print("Cannot find SplitContaier in file system dock.")
		return
		
	# first split
	file_tree = sc.find_child("@Tree*", false, false)
	if not file_tree:
		printt("Cannot find Tree in file sytem dock.")
		return
	file_tree.item_activated.connect(_on_file_tree_item_activated)
	
	# second split
	file_item_list = sc.find_child("@FileSystemList*", true, false)
	file_item_list.item_activated.connect(_on_file_item_list_item_activated)
	
func _on_file_tree_item_activated():
	var selected = file_tree.get_selected()
	if selected:
		var path = selected.get_metadata(0) as String
		if path.get_extension() == "xml":
			open_file(path)
			
func _on_file_item_list_item_activated(index: int):
	var path = file_item_list.get_item_metadata(index) as String
	if path.get_extension() == "xml":
		open_file(path)
		
func _on_file_system_dock_popup_menu_idex_pressed(index: int):
	var fs_dock = EditorInterface.get_file_system_dock()
	for i in fs_dock.get_children(true):
		if i is PopupMenu:
			for j in i.item_count:
				if i.get_item_text(j) in ["Open", tr("Open")]:
					if i.get_item_text(index) == ["Open", tr("Open")]:
						var path = EditorInterface.get_current_path()
						if path.get_extension() == "xml":
							open_file(path)
							return
							
func _on_close_requested() -> void:
	hide()

func open_file(path: String):
	transient = false
	if visible:
		if mode != MODE_WINDOWED:
			mode = MODE_WINDOWED
		grab_focus()
	else:
		if inited:
			popup_centered()
		else:
			popup_centered_ratio(0.6)
			inited = true
			
	if path != "":
		xml_editor_panel.open_file(path)
