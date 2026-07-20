class_name GDSQLGodotVariantCodec
extends RefCounted

const ENCODED_TYPE_KEY := "__gdsql_encoded_type__"
const NULL_TYPE := "null"
const RESOURCE_TYPE := "resource"
const RESOURCE_DATA_KEY := "data"


func encode(value: Variant) -> Variant:
	if value == null:
		return { ENCODED_TYPE_KEY: NULL_TYPE }
	if value is Resource:
		return {
			ENCODED_TYPE_KEY: RESOURCE_TYPE,
			RESOURCE_DATA_KEY: var_to_bytes_with_objects(value),
		}
	return value


func decode(value: Variant) -> Variant:
	if value is Dictionary \
			and value.size() == 1 \
			and value.get(ENCODED_TYPE_KEY) == NULL_TYPE:
		return null
	if value is Dictionary \
			and value.size() == 2 \
			and value.get(ENCODED_TYPE_KEY) == RESOURCE_TYPE \
			and value.get(RESOURCE_DATA_KEY) is PackedByteArray:
		return bytes_to_var_with_objects(value.get(RESOURCE_DATA_KEY))
	return value
