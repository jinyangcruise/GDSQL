@tool
extends ScrollContainer

## 通过该信号可以把需要在检查器中查看的对象发送给EditorInterface
signal inspect_object(object: Object, for_property: String, inspector_only: bool)

@onready var table: VBoxContainer = $VBoxContainer/Table
@onready var line_edit_schema: LineEdit = $VBoxContainer/HBoxContainer/LineEditSchema
@onready var line_edit_table_name: LineEdit = $VBoxContainer/HBoxContainer2/LineEditTableName
@onready var text_edit_comment: TextEdit = $VBoxContainer/HBoxContainer3/TextEditComment

@export var aaa: Variant.Type

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
	
static var types = [
	"TYPE_NIL:0",
	"TYPE_BOOL:1",
	"TYPE_INT:2",
	"TYPE_FLOAT:3",
	"TYPE_STRING:4",
	"TYPE_VECTOR2:5",
	"TYPE_VECTOR2I:6",
	"TYPE_RECT2:7",
	"TYPE_RECT2I:8",
	"TYPE_VECTOR3:9",
	"TYPE_VECTOR3I:10",
	"TYPE_TRANSFORM2D:11",
	"TYPE_VECTOR4:12",
	"TYPE_VECTOR4I:13",
	"TYPE_PLANE:14",
	"TYPE_QUATERNION:15",
	"TYPE_AABB:16",
	"TYPE_BASIS:17",
	"TYPE_TRANSFORM3D:18",
	"TYPE_PROJECTION:19",
	"TYPE_COLOR:20",
	"TYPE_STRING_NAME:21",
	"TYPE_NODE_PATH:22",
	"TYPE_RID:23",
	"TYPE_OBJECT:24",
	"TYPE_CALLABLE:25",
	"TYPE_SIGNAL:26",
	"TYPE_DICTIONARY:27",
	"TYPE_ARRAY:28",
	"TYPE_PACKED_BYTE_ARRAY:29",
	"TYPE_PACKED_INT32_ARRAY:30",
	"TYPE_PACKED_INT64_ARRAY:31",
	"TYPE_PACKED_FLOAT32_ARRAY:32",
	"TYPE_PACKED_FLOAT64_ARRAY:33",
	"TYPE_PACKED_STRING_ARRAY:34",
	"TYPE_PACKED_VECTOR2_ARRAY:35",
	"TYPE_PACKED_VECTOR3_ARRAY:36",
	"TYPE_PACKED_COLOR_ARRAY:37",
	"TYPE_MAX:38",
]

static var property_hints = [
	"PROPERTY_HINT_NONE:0",
	"PROPERTY_HINT_RANGE:1",
	"PROPERTY_HINT_ENUM:2",
	"PROPERTY_HINT_ENUM_SUGGESTION:3",
	"PROPERTY_HINT_EXP_EASING:4",
	"PROPERTY_HINT_LINK:5",
	"PROPERTY_HINT_FLAGS:6",
	"PROPERTY_HINT_LAYERS_2D_RENDER:7",
	"PROPERTY_HINT_LAYERS_2D_PHYSICS:8",
	"PROPERTY_HINT_LAYERS_2D_NAVIGATION:9",
	"PROPERTY_HINT_LAYERS_3D_RENDER:10",
	"PROPERTY_HINT_LAYERS_3D_PHYSICS:11",
	"PROPERTY_HINT_LAYERS_3D_NAVIGATION:12",
	"PROPERTY_HINT_FILE:13",
	"PROPERTY_HINT_DIR:14",
	"PROPERTY_HINT_GLOBAL_FILE:15",
	"PROPERTY_HINT_GLOBAL_DIR:16",
	"PROPERTY_HINT_RESOURCE_TYPE:17",
	"PROPERTY_HINT_MULTILINE_TEXT:18",
	"PROPERTY_HINT_EXPRESSION:19",
	"PROPERTY_HINT_PLACEHOLDER_TEXT:20",
	"PROPERTY_HINT_COLOR_NO_ALPHA:21",
	"PROPERTY_HINT_OBJECT_ID:22",
	"PROPERTY_HINT_TYPE_STRING:23",
	"PROPERTY_HINT_NODE_PATH_TO_EDITED_NODE:24",
	"PROPERTY_HINT_OBJECT_TOO_BIG:25",
	"PROPERTY_HINT_NODE_PATH_VALID_TYPES:26",
	"PROPERTY_HINT_SAVE_FILE:27",
	"PROPERTY_HINT_GLOBAL_SAVE_FILE:28",
	"PROPERTY_HINT_INT_IS_OBJECTID:29",
	"PROPERTY_HINT_INT_IS_POINTER:30",
	"PROPERTY_HINT_ARRAY_TYPE:31",
	"PROPERTY_HINT_LOCALE_ID:32",
	"PROPERTY_HINT_LOCALIZABLE_STRING:33",
	"PROPERTY_HINT_NODE_TYPE:34",
	"PROPERTY_HINT_HIDE_QUATERNION_EDIT:35",
	"PROPERTY_HINT_PASSWORD:36",
	"PROPERTY_HINT_LAYERS_AVOIDANCE:37",
	"PROPERTY_HINT_MAX:38",
]

# 为Data Type和Hint设置自定义显示控件和数据绑定逻辑，否则会默认显示为一个整数，难以让用户分辨
static var update_callback := func(new_value, property, dict_obj_ref: WeakRef, readable_map: Array):
	var dict_obj = dict_obj_ref.get_ref() as DictionaryObject
	if dict_obj:
		var label = dict_obj.get_custom_display_control(property) as Label
		label.text = (readable_map[new_value] as String).split(":")[0]

static func _static_init() -> void:
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/editor/editor_inspector.cpp#L4129
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/modules/gdscript/gdscript_parser.cpp#L4020
	_hint_string["Data Type"]["hint_string"] = ",".join(types)
	_hint_string["Hint"]["hint_string"] = ",".join(property_hints)

func _ready() -> void:
	if schema != null:
		schema = schema
	if table_name != null:
		table_name = table_name
	if comment != null:
		comment = comment
		
	table.inspect_object.connect(func(object, for_property, inspector_only): 
		inspect_object.emit(object, for_property, inspector_only))
		
	var label_data_type := Label.new()
	label_data_type.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label_data_type.auto_translate = false
	label_data_type.localize_numeral_system = false
	
	var label_hint = label_data_type.duplicate()
	
	var row := DictionaryObject.new([
		table.columns, 
		["idnew_table", TYPE_INT, PROPERTY_HINT_NONE , "", true, true, false, true, "", ""]
	], _hint_string)
	row.set_custom_display_control("Data Type", label_data_type, update_callback.bind("Data Type", weakref(row), types), true)
	row.set_custom_display_control("Hint", label_hint, update_callback.bind("Hint", weakref(row), property_hints), true)
	
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
	row.set_custom_display_control("Data Type", label_data_type, update_callback.bind("Data Type", weakref(row), types), true)
	row.set_custom_display_control("Hint", label_hint, update_callback.bind("Hint", weakref(row), property_hints), true)
	
	datas.push_back(row)
	table.datas = datas
