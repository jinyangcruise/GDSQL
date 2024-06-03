@tool
extends ScrollContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var table: VBoxContainer = $VBoxContainer/Table
@onready var line_edit_schema: LineEdit = $VBoxContainer/HBoxContainer/LineEditSchema
@onready var line_edit_table_name: LineEdit = $VBoxContainer/HBoxContainer2/LineEditTableName
@onready var text_edit_comment: TextEdit = $VBoxContainer/HBoxContainer3/TextEditComment
@onready var line_edit_data_file_path = $VBoxContainer/HBoxContainer4/LineEditDataFilePath
@onready var line_edit_data_file_size = $VBoxContainer/HBoxContainer5/LineEditDataFileSize
@onready var line_edit_total_data_count = $VBoxContainer/HBoxContainer6/LineEditTotalDataCount
@onready var button_enter_password = $VBoxContainer/HBoxContainer6/ButtonEnterPassword

const CONFIG_EXTENSION = ".cfg"

var schema: String:
	set(val):
		schema = val
		if line_edit_schema and is_inside_tree():
			line_edit_schema.text = val

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
			
var data_file_path: String:
	set(val):
		data_file_path = val
		if line_edit_data_file_path and is_inside_tree():
			line_edit_data_file_path.text = val
			
var data_file_size: String:
	set(val):
		data_file_size = val
		if line_edit_data_file_size and is_inside_tree():
			line_edit_data_file_size.text = val
			
var total_data_count: String:
	set(val):
		total_data_count = val
		if is_inside_tree():
			line_edit_total_data_count.text = val
			if val == "":
				line_edit_total_data_count.hide()
				button_enter_password.show()
			else:
				line_edit_total_data_count.show()
				button_enter_password.hide()
				
var update_total_data_count: Callable

var raw_datas: Array = []:
	set(val):
		raw_datas = val
		if table and is_inside_tree():
			var datas = []
			for i: Dictionary in raw_datas:
				var row = _gen_row()
				for column in table.columns:
					row._set(column, i.get(column, null))
				datas.push_back(row)
			table.datas = datas

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
	table.column_tips = ["字段名称", "数据类型", "检查器属性提示", "提示字符串", 
	"是否为主键", "是否非空", "是否唯一", "是否自增", "默认值（支持表达式）", "备注"] as Array[String]
	table.columns = ["Column Name", "Data Type", "Hint", "Hint String", "PK", "NN", "UQ", "AI", "Default(Expression)", "Comment"]
	
	if schema != "":
		schema = schema
	if table_name != "":
		table_name = table_name
	if comment != "":
		comment = comment
	if data_file_path != "":
		data_file_path = data_file_path
	if data_file_size != "":
		data_file_size = data_file_size
	total_data_count = total_data_count
	if not raw_datas.is_empty():
		raw_datas = raw_datas
		
func _exit_tree():
	raw_datas = []
	for i: DictionaryObject in table.datas:
		i.get_custom_display_control("Data Type").queue_free()
		i.get_custom_display_control("Hint").queue_free()
	update_total_data_count = Callable()
	mgr = null
	
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
	
func _on_button_apply_pressed():
	queue_free()


func _on_button_enter_password_pressed():
	if update_total_data_count != null:
		mgr.request_user_enter_password.emit(schema, table_name, "", update_total_data_count)


func _on_button_show_in_file_manager_pressed():
	if data_file_path != "":
		var path = ProjectSettings.globalize_path(data_file_path.split("(")[0])
		OS.shell_show_in_file_manager(path, true)


func _on_button_open_config_pressed():
	if schema != "" and table_name != "":
		var path = ProjectSettings.globalize_path(mgr.databases[schema]["config_path"] + table_name + CONFIG_EXTENSION)
		OS.shell_open(path)
