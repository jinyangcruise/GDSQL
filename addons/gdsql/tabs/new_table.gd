@tool
extends ScrollContainer

signal button_apply_pressed(sechema: String, schema_path: String, table_name: String, columns: Array, id: String)

@onready var table: VBoxContainer = $VBoxContainer/Table
@onready var line_edit_schema: LineEdit = $VBoxContainer/HBoxContainer/LineEditSchema
@onready var line_edit_table_name: LineEdit = $VBoxContainer/HBoxContainer2/LineEditTableName
@onready var text_edit_comment: TextEdit = $VBoxContainer/HBoxContainer3/TextEditComment

var schema: String:
	set(val):
		schema = val
		if line_edit_schema and is_inside_tree():
			line_edit_schema.text = val
			
var schema_path: String
			
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
			
var datas: Array = []

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
		
	var label_data_type := Label.new()
	label_data_type.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label_data_type.auto_translate = false
	label_data_type.localize_numeral_system = false
	
	var label_hint = label_data_type.duplicate()
	
	var row := DictionaryObject.new([
		table.columns, 
		["idnew_table", TYPE_INT, PROPERTY_HINT_NONE , "", true, true, false, true, "", ""]
	], _hint_string)
	row.set_custom_display_control("Data Type", label_data_type, update_callback.bind("Data Type", weakref(row), DataTypeDef.DATA_TYPE_NAMES), true)
	row.set_custom_display_control("Hint", label_hint, update_callback.bind("Hint", weakref(row), DataTypeDef.PROPERTY_HINT_NAMES), true)
	
	datas.push_back(row)
	table.datas = datas


func _on_button_new_column_pressed() -> void:
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
	
	datas.push_back(row)
	table.datas = datas


func _on_button_apply_pressed() -> void:
	var curr_schema = line_edit_schema.text.strip_edges()
	var curr_table_name = line_edit_table_name.text.strip_edges()
	if curr_schema.is_empty() or curr_table_name.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "schema and table name must be set!"
		add_child(dialog)
		dialog.popup_centered()
		dialog.close_requested.connect(func():
			dialog.queue_free()
		)
		return
		
	var column_infos = []
	for i in table.datas:
		column_infos.push_back(i._data)
	button_apply_pressed.emit(schema, schema_path, curr_table_name, column_infos, name)
