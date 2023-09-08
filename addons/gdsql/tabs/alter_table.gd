@tool
extends ScrollContainer

signal button_apply_pressed(sechema: String, old_table_name: String, new_table_name: String, comments: String, columns: Array, id: String)

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var table: VBoxContainer = $VBoxContainer/Table
@onready var line_edit_schema: LineEdit = $VBoxContainer/HBoxContainer/LineEditSchema
@onready var line_edit_table_name: LineEdit = $VBoxContainer/HBoxContainer2/LineEditTableName
@onready var text_edit_comment: TextEdit = $VBoxContainer/HBoxContainer3/TextEditComment
@onready var popup_menu = $PopupMenu

var schema: String:
	set(val):
		schema = val
		if line_edit_schema and is_inside_tree():
			line_edit_schema.text = val
			
var old_table_name: String

var table_name: String:
	set(val):
		table_name = val
		if line_edit_table_name and is_inside_tree():
			line_edit_table_name.text = val
			
var comment: String:
	set(val):
		comment = val
		if text_edit_comment and is_inside_tree():
			text_edit_comment.text = val
			
var raw_datas: Array = []:
	set(val):
		raw_datas = val
		if table and is_inside_tree():
			datas = []
			for i: Dictionary in raw_datas:
				var row = _gen_row()
				for column in table.columns:
					row._set(column, i.get(column, null))
				datas.push_back(row)
			table.datas = datas
			printt("qeeeeeee", raw_datas, datas)
			
var datas: Array = [] # array of dictionary object

static var _hint_string = {
		"Data Type": {
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ""
		},
		"Hint": {
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ""
		},
		"Default(Expression)": {
			"hint": PROPERTY_HINT_EXPRESSION,
			"hint_string": ""
		},
		"Comment": {
			"hint": PROPERTY_HINT_MULTILINE_TEXT,
			"hint_string": ""
		},
	}


static func _static_init() -> void:
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/editor/editor_inspector.cpp#L4129
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/modules/gdscript/gdscript_parser.cpp#L4020
	_hint_string["Data Type"]["hint_string"] = ",".join(DataTypeDef.DATA_TYPE_NAME_INDEXES)
	_hint_string["Hint"]["hint_string"] = ",".join(DataTypeDef.PROPERTY_HINT_INDEXES)

# 为Data Type和Hint设置自定义显示控件和数据绑定逻辑，否则会默认显示为一个整数，难以让用户分辨
static func update_callback(new_value, property, dict_obj_ref: WeakRef, readable_map: Array):
	var dict_obj = dict_obj_ref.get_ref() as DictionaryObject
	if dict_obj:
		var label = dict_obj.get_custom_display_control(property) as Label
		#label.text = (readable_map[new_value] as String).split(":")[0]
		label.text = readable_map[new_value]

func _ready() -> void:
	if schema != null:
		schema = schema
	if table_name != null:
		table_name = table_name
	if comment != null:
		comment = comment
	if not raw_datas.is_empty():
		raw_datas = raw_datas

func _on_button_new_column_pressed() -> void:
	var row = _gen_row()
	datas.push_back(row)
	table.datas = datas
	
func _gen_row() -> DictionaryObject:
	var label_data_type := Label.new()
	label_data_type.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label_data_type.auto_translate = false
	label_data_type.localize_numeral_system = false
	
	var label_hint = label_data_type.duplicate()
	
	var row := DictionaryObject.new([
		table.columns, 
		["new_table_col", TYPE_INT, PROPERTY_HINT_NONE, "", false, false, false, false, "", ""]
	], _hint_string)
	row.set_custom_display_control("Data Type", label_data_type, update_callback.bind("Data Type", weakref(row), DataTypeDef.DATA_TYPE_NAMES), true)
	row.set_custom_display_control("Hint", label_hint, update_callback.bind("Hint", weakref(row), DataTypeDef.PROPERTY_HINT_NAMES), true)
	return row


func _on_button_apply_pressed() -> void:
	var curr_schema = line_edit_schema.text.strip_edges()
	var curr_table_name = line_edit_table_name.text.strip_edges()
	if curr_schema.is_empty() or curr_table_name.is_empty():
		mgr.create_accept_dialog(self, "schema and table name must be set!")
		return
		
	var comments = text_edit_comment.text
		
	var column_infos = []
	for i in table.datas:
		column_infos.push_back(i._data)
	button_apply_pressed.emit(schema, old_table_name, curr_table_name, comments, column_infos, name)

var selected_row_index = -1
func _on_table_row_clicked(row_index, mouse_button_index, _data):
	if mouse_button_index == 2:
		popup_menu.position = DisplayServer.mouse_get_position()
		popup_menu.popup()
		selected_row_index = row_index


func _on_popup_menu_index_pressed(index):
	var datas: Array = table.datas
	match popup_menu.get_item_text(index):
		"remove":
			datas.remove_at(selected_row_index)
			table.datas = datas
		"move top":
			if selected_row_index > 0:
				var data = datas[selected_row_index]
				datas.remove_at(selected_row_index)
				datas.push_front(data)
				table.datas = datas
		"move up":
			if selected_row_index > 0:
				var data = datas[selected_row_index]
				datas.remove_at(selected_row_index)
				datas.insert(selected_row_index - 1, data)
				table.datas = datas
		"move down":
			if selected_row_index < datas.size() - 1:
				var data = datas[selected_row_index]
				datas.remove_at(selected_row_index)
				datas.insert(selected_row_index + 1, data)
				table.datas = datas
		"move bottom":
			if selected_row_index < datas.size() - 1:
				var data = datas[selected_row_index]
				datas.remove_at(selected_row_index)
				datas.push_back(data)
				table.datas = datas
		"insert above":
			var row = _gen_row()
			datas.insert(selected_row_index, row)
			table.datas = datas
		"insert below":
			var row = _gen_row()
			datas.insert(selected_row_index + 1, row)
			table.datas = datas
