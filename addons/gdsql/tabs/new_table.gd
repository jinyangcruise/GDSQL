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


func _ready() -> void:
	if schema != null:
		schema = schema
	if table_name != null:
		table_name = table_name
	if comment != null:
		comment = comment
		
	table.inspect_object.connect(func(object, for_property, inspector_only): 
		inspect_object.emit(object, for_property, inspector_only))
		
		
	var types = [
		"TYPE_NIL", "TYPE_BOOL", "TYPE_INT", "TYPE_FLOAT", "TYPE_STRING", "TYPE_VECTOR2", 
		"TYPE_VECTOR2I", "TYPE_RECT2", "TYPE_RECT2I", "TYPE_VECTOR3", "TYPE_VECTOR3I", 
		"TYPE_TRANSFORM2D", "TYPE_VECTOR4", "TYPE_VECTOR4I", "TYPE_PLANE", "TYPE_QUATERNION", 
		"TYPE_AABB", "TYPE_BASIS", "TYPE_TRANSFORM3D", "TYPE_PROJECTION", "TYPE_COLOR", 
		"TYPE_STRING_NAME", "TYPE_NODE_PATH", "TYPE_RID", "TYPE_OBJECT", "TYPE_CALLABLE", 
		"TYPE_SIGNAL", "TYPE_DICTIONARY", "TYPE_ARRAY", "TYPE_PACKED_BYTE_ARRAY", 
		"TYPE_PACKED_INT32_ARRAY", "TYPE_PACKED_INT64_ARRAY", "TYPE_PACKED_FLOAT32_ARRAY", 
		"TYPE_PACKED_FLOAT64_ARRAY", "TYPE_PACKED_STRING_ARRAY", "TYPE_PACKED_VECTOR2_ARRAY", 
		"TYPE_PACKED_VECTOR3_ARRAY", "TYPE_PACKED_COLOR_ARRAY", "TYPE_MAX"
	]
	var types_valid = []
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/editor/editor_inspector.cpp#L4129
	# https://github.com/godotengine/godot/blob/da81ca62a5f6d615516929896caa0b6b09ceccfc/modules/gdscript/gdscript_parser.cpp#L4020
	for i in types.size():
		if i == TYPE_NIL or i == TYPE_RID or i == TYPE_CALLABLE or i == TYPE_SIGNAL or i == TYPE_MAX:
			continue # not editable by inspector.
		if i == TYPE_OBJECT:
			types[i] = "Resource"
		types_valid.push_back("%s:%d" % [(types[i] as String).replace("TYPE_", "").capitalize(), i])
	
	var row := DictionaryObject.new([table.columns, ["idnew_table", TYPE_INT, true, true, false, true, "", ""]], {
		"Data Type": {
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ",".join(types_valid)
		}
	})
	datas.push_back(row)
	table.datas = datas
