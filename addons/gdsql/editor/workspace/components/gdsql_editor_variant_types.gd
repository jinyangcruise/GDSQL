class_name GDSQLEditorVariantTypes
extends RefCounted
## Editor-facing catalog of Variant types supported by the current storage
## codec and ConfigFile backend.

const SUPPORTED_TYPES: Array[Variant.Type] = [
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_STRING_NAME,
	TYPE_NODE_PATH,
	TYPE_VECTOR2,
	TYPE_VECTOR2I,
	TYPE_RECT2,
	TYPE_RECT2I,
	TYPE_VECTOR3,
	TYPE_VECTOR3I,
	TYPE_TRANSFORM2D,
	TYPE_VECTOR4,
	TYPE_VECTOR4I,
	TYPE_PLANE,
	TYPE_QUATERNION,
	TYPE_AABB,
	TYPE_BASIS,
	TYPE_TRANSFORM3D,
	TYPE_PROJECTION,
	TYPE_COLOR,
	TYPE_DICTIONARY,
	TYPE_ARRAY,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY,
	TYPE_PACKED_COLOR_ARRAY,
	TYPE_PACKED_VECTOR4_ARRAY,
	TYPE_OBJECT,
]


static func populate(button: OptionButton) -> void:
	button.clear()
	for data_type in SUPPORTED_TYPES:
		button.add_item(display_name(data_type), data_type)


static func select_type(button: OptionButton, data_type: Variant.Type) -> void:
	for index in button.item_count:
		if button.get_item_id(index) == data_type:
			button.select(index)
			return


static func selected_type(button: OptionButton) -> Variant.Type:
	return int(button.get_selected_id()) as Variant.Type


static func display_name(data_type: Variant.Type) -> String:
	return "Resource" if data_type == TYPE_OBJECT else type_string(data_type)
