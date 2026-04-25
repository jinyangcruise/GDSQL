@tool
extends Window

@onready var xml_editor_panel: PanelContainer = %XMLEditorPanel

var inited = false

var file_tree: Tree
var file_item_list: ItemList
var _native_find_in_files: Object
var _native_on_find_in_files_result_selected: Callable
var _native_on_find_in_files_result_selected_flags

func _ready() -> void:
	transient = false
	set_translation_domain("GDSQL")
	bind_file_system_dock_popup_menu()
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		%XMLEditorPanel.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"PanelForeground", &"EditorStyles"))
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible and DisplayServer.has_method("window_set_icon"):
			DisplayServer.window_set_icon(load("res://addons/gdsql/gbatis/img/xml.svg").get_image(), get_window_id())
			
func _exit_tree() -> void:
	if _native_find_in_files and _native_on_find_in_files_result_selected.is_valid():
		if not _native_find_in_files.is_connected(&"result_selected", _native_on_find_in_files_result_selected):
			_native_find_in_files.connect(&"result_selected", _native_on_find_in_files_result_selected, 
				_native_on_find_in_files_result_selected_flags)
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
	var trees = fs_dock.find_children("@Tree*", "Tree", true, false)
	for tree: Tree in trees:
		if tree.accessibility_name == tr("Directories"):
			file_tree = tree
			break
			
	if not file_tree:
		push_warning("Cannot find FileSystemTree in file system dock.")
		return
		
	file_tree.item_activated.connect(_on_file_tree_item_activated)
	
	# second split
	file_item_list = fs_dock.find_children("@FileSystemList*", "FileSystemList", true, false)[0]
	file_item_list.item_activated.connect(_on_file_item_list_item_activated)
	
	# Find in files bind
	for i in EditorInterface.get_script_editor().get_incoming_connections():
		var s: Signal = i.signal
		if s.get_name() == &"result_selected" and \
		(i.callable as Callable).get_method() == "ScriptEditor::_on_find_in_files_result_selected":
			_native_find_in_files = s.get_object()
			_native_on_find_in_files_result_selected = i.callable
			_native_on_find_in_files_result_selected_flags = i.flags
			s.get_object().disconnect(&"result_selected", i.callable)
			s.get_object().connect(&"result_selected", _proxy_on_find_in_files_result_selected, i.flags)
			break
			
func _on_file_tree_item_activated():
	var selected = file_tree.get_selected()
	if selected:
		var path = selected.get_metadata(0) as String
		if path.get_extension().to_lower() == "xml":
			open_file(path)
			
func _on_file_item_list_item_activated(index: int):
	var path = file_item_list.get_item_metadata(index) as String
	if path.get_extension().to_lower() == "xml":
		open_file(path)
		
func _on_file_system_dock_popup_menu_idex_pressed(index: int):
	var fs_dock = EditorInterface.get_file_system_dock()
	for i in fs_dock.get_children(true):
		if i is PopupMenu:
			for j in i.item_count:
				if i.get_item_text(j) in ["Open", tr("Open")]:
					if i.get_item_text(index) in ["Open", tr("Open")]:
						var path = EditorInterface.get_current_path()
						if path.get_extension().to_lower() == "xml":
							open_file(path)
							return
							
func _proxy_on_find_in_files_result_selected(fpath: String, line_number: int, begin: int, end: int):
	if fpath.get_extension().to_lower() == "xml":
		open_file(fpath, line_number - 1, begin, end)
	else:
		_native_on_find_in_files_result_selected.call(fpath, line_number, begin, end)
		
func _on_close_requested() -> void:
	hide()
	
func open_file(path: String, p_line: int = 0, p_begin: int = -1, p_end: int = -1):
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
		xml_editor_panel.open_file(path, p_line, p_begin, p_end)
