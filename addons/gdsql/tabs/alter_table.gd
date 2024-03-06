@tool
extends ScrollContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var table: VBoxContainer = $VBoxContainer/Table
@onready var line_edit_schema: LineEdit = $VBoxContainer/HBoxContainer/LineEditSchema
@onready var line_edit_table_name: LineEdit = $VBoxContainer/HBoxContainer2/LineEditTableName
@onready var text_edit_comment: TextEdit = $VBoxContainer/HBoxContainer3/TextEditComment
@onready var check_box_valid_if_not_exist = $VBoxContainer/HBoxContainer4/CheckBoxValidIfNotExist
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
			
var valid_if_not_exist: bool:
	set(val):
		valid_if_not_exist = val
		if check_box_valid_if_not_exist and is_inside_tree():
			check_box_valid_if_not_exist.button_pressed = val
			
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
	table.ratios = [4.0, 4.0, 3.0, 2.0, 20.0, 19.0, 18.0, 17.0, 1.0, 1.0] as Array[float]
	table.column_tips = ["字段名称", "数据类型", "检查器属性提示", "提示字符串", "是否为主键", "是否非空", "是否唯一", "是否自增", "默认值（支持表达式）", "备注"] as Array[String]
	table.columns = ["Column Name", "Data Type", "Hint", "Hint String", "PK", "NN", "UQ", "AI", "Default(Expression)", "Comment"]
	
	if schema != "":
		schema = schema
	if table_name != "":
		table_name = table_name
	if comment != "":
		comment = comment
	valid_if_not_exist = valid_if_not_exist
	if not raw_datas.is_empty():
		raw_datas = raw_datas
		
func _exit_tree():
	raw_datas = []
	for i: DictionaryObject in datas:
		i.get_custom_display_control("Data Type").queue_free()
		i.get_custom_display_control("Hint").queue_free()
	datas.clear()
	mgr = null

func _on_button_new_column_pressed() -> void:
	var row = _gen_row()
	table.append_data(row)
	table.row_grab_focus(table.datas.size() - 1)
	
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
	row.set_custom_display_control("Data Type", label_data_type, 
		update_callback.bind("Data Type", weakref(row), DataTypeDef.DATA_TYPE_NAMES), true)
	row.set_custom_display_control("Hint", label_hint, 
		update_callback.bind("Hint", weakref(row), DataTypeDef.PROPERTY_HINT_NAMES), true)
	return row


func _on_button_apply_pressed() -> void:
	var curr_schema = line_edit_schema.text.strip_edges()
	var curr_table_name = line_edit_table_name.text.strip_edges()
	if curr_schema.is_empty() or curr_table_name.is_empty():
		return mgr.create_accept_dialog("schema and table name must be set!")
		
	var comments = text_edit_comment.text
	var valid = check_box_valid_if_not_exist.button_pressed
		
	var column_infos = []
	for i in table.datas:
		column_infos.push_back(i._data)
		
	mgr.user_confirm_alter_table.emit(schema, old_table_name, curr_table_name, comments, valid, column_infos, name)

var selected_row_index = -1
func _on_table_row_clicked(row_index, mouse_button_index, _data):
	if mouse_button_index == 2:
		popup_menu.position = DisplayServer.mouse_get_position()
		popup_menu.popup()
		selected_row_index = row_index


func _on_popup_menu_index_pressed(index):
	var _datas: Array = table.datas
	match popup_menu.get_item_text(index):
		"remove":
			table.remove_data_at(selected_row_index, true)
		"move top":
			if selected_row_index > 0:
				table.move_data(selected_row_index, 0)
		"move up":
			if selected_row_index > 0:
				table.move_data(selected_row_index, selected_row_index - 1)
		"move down":
			if selected_row_index < table.datas.size() - 1:
				table.move_data(selected_row_index, selected_row_index + 1)
		"move bottom":
			if selected_row_index < table.datas.size() - 1:
				table.move_data(selected_row_index, table.datas.size() - 1)
		"insert above":
			var row = _gen_row()
			table.insert_data(selected_row_index, row)
		"insert below":
			var row = _gen_row()
			table.insert_data(selected_row_index + 1, row)


func _on_button_cancel_pressed():
	queue_free()
