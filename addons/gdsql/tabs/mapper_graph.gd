@tool
extends VSplitContainer

@onready var button_open: Button = $VBoxContainer/HFlowContainer/ButtonOpen
@onready var button_save: Button = $VBoxContainer/HFlowContainer/ButtonSave
@onready var button_save_as: Button = $VBoxContainer/HFlowContainer/ButtonSaveAs
@onready var button_add_node: Button = $VBoxContainer/HFlowContainer/ButtonAddNode
@onready var line_edit_save_path: LineEdit = $VBoxContainer/HFlowContainer/LineEditSavePath
@onready var option_button_choose_file: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonChooseFile
@onready var button_run_selected: Button = $VBoxContainer/HFlowContainer/ButtonRunSelected
@onready var button_run: Button = $VBoxContainer/HFlowContainer/ButtonRun
@onready var button_preview: Button = $VBoxContainer/HFlowContainer/ButtonPreview

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")


signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var graph_edit: GraphEdit = $VBoxContainer/GraphEdit

const EXTENSION = "*.gdmappergraph"

func _ready() -> void:
	pass
	
func load_mapper_file(path):
	var config = ImprovedConfigFile.new()
	config.load(path)
	var nodes = config.get_value("data", "nodes", {})
	var connections = config.get_value("data", "connections", [])
	
	# genarate nodes
	graph_edit._load_nodes(nodes, connections, Vector2.ZERO, false, false)
	
	set_meta("type", "mapper_graph")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
func load_data(info: Dictionary):
	graph_edit.add_item(info, {})
	
func _on_button_open_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.add_filter(EXTENSION, "GDSQL MAPPER GRAPH File")
	editor_file_dialog.file_selected.connect(func(path: String):
		request_open_file.emit(path)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or \
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(get_meta("file_path"))
		change_tab_title.emit(self, get_meta("file_name"))
		return
		
	_on_button_save_as_pressed()
	
func _on_button_save_as_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter(EXTENSION, "GDSQL MAPPER File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or \
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(path)
		var file_name = path.get_file()
		change_tab_title.emit(self, file_name)
		set_meta("type", "mapper_graph")
		set_meta("is_file", true)
		set_meta("file_path", path)
		set_meta("file_name", file_name)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func _on_button_add_node_pressed() -> void:
	mgr.create_accept_dialog(button_add_node.tooltip_text)
	
func _on_option_button_choose_file_item_selected(access: int) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.filters = PackedStringArray([EXTENSION])
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_save_path.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
func _on_button_run_selected_pressed() -> void:
	pass # Replace with function body.


func _on_button_run_pressed() -> void:
	pass # Replace with function body.


func _on_button_preview_pressed() -> void:
	pass # Replace with function body.
