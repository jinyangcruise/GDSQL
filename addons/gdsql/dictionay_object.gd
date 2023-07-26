extends RefCounted
class_name DictionaryObject

var _origin: Dictionary
var _data: Dictionary

func _init(data) -> void:
	if data is Dictionary:
		_data = data
	elif data is Array and data.size() == 2 and data[0] is Array and data[1] is Array:
		_data = {}
		for i in data[0].size():
			_data[data[0][i]] = data[1][i]
	
func _get(property: StringName) -> Variant:
	if _data.has(property):
		return _data[property]
	return null
	
func _set(property: StringName, value: Variant) -> bool:
	if _data.has(property):
		if not _origin.has(property):
			_origin[property] = _data[property]
		_data[property] = value
		return true
	return false
	
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for key in _data:
		properties.append({
			"name": key,
			"type": typeof(_data[key]),
			"usage": PROPERTY_USAGE_DEFAULT,
			#"hint": PROPERTY_HINT_ENUM,
			#"hint_string": "Wooden,Iron,Golden,Enchanted"
		})
	return properties
	
func _property_can_revert(property: StringName) -> bool:
	return _data.has(property)
	
func _property_get_revert(property: StringName) -> Variant:
	if _origin.has(property):
		return _origin[property]
	if _data.has(property):
		return _data[property]
	return null


