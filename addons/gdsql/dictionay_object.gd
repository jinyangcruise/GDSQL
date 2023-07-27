extends RefCounted
class_name DictionaryObject

var _origin: Dictionary
var _data: Dictionary
var _hint: Dictionary
var _update_callback: Dictionary

## data： 一个key-value形成的字典数据。或一个长度为2的数组，第一个元素是key的一维数组，第二个元素是value的一维数组
## hint： 一个key-dictionay字典数据。key为data中的key，dictionary为包含"hint"和"hint_string"键的数据。@see PropertyHint 
func _init(data, hint: Dictionary = {}) -> void:
	_hint = hint
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
		if _update_callback and _update_callback.has(property):
			_update_callback[property].call(value)
		return true
	return false
	
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for key in _data:
		properties.append({
			"name": key,
			"type": typeof(_data[key]),
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_NONE if not (_hint.has(key) and _hint[key].has("hint")) else _hint[key]["hint"],
			"hint_string": "" if not (_hint.has(key) and _hint[key].has("hint_string")) else _hint[key]["hint_string"]
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
	
func set_update_callback(property: String, callback: Callable) -> void:
	_update_callback[property] = callback
	

