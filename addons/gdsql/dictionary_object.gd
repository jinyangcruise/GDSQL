extends RefCounted
class_name DictionaryObject

signal value_changed(prop: StringName, new_value: Variant, old_value: Variant)

var _origin: Dictionary
var _data: Dictionary
var _hint: Dictionary
var _usage: Dictionary
var _update_callback: Dictionary
var _custom_display_control: Dictionary
var _read_only: bool
## 连接属性
var _duplicate_property: Dictionary
var _prop_index_cache: Dictionary
var _duplicate_property_name: Dictionary

## data： 一个key-value形成的字典数据。或一个长度为2的数组，第一个元素是key的一维数组，第二个元素是value的一维数组
## hint： 一个key-dictionary字典数据。key为data中的key，dictionary为包含"hint"和"hint_string"键的数据。@see PropertyHint 
## 是否只读
func _init(data, hint: Dictionary = {}, read_only: bool = false) -> void:
	_hint = hint
	_read_only = read_only
	if data is Dictionary:
		_data = data
	elif data is Array and data.size() == 2 and data[0] is Array and data[1] is Array:
		_data = {}
		for i in data[0].size():
			_data[data[0][i]] = data[1][i]
			
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		_origin = {}
		_data = {}
		_hint = {}
		if _update_callback:
			_update_callback.clear()
		if _custom_display_control:
			_custom_display_control.clear()
		
func get_data() -> Dictionary:
	return _data
	
func reset_data(data, hint = null):
	_data = data
	_usage = {}
	_duplicate_property = {}
	_prop_index_cache = {}
	if hint != null:
		_hint = hint
	notify_property_list_changed()
	
func revert():
	if _origin:
		for k in _origin:
			_data[k] = _origin[k]
		_origin.clear()
	
func reset_hint(hint: Dictionary):
	_hint = hint
	notify_property_list_changed()
	
func reset_read_only(read_only: bool):
	_read_only = read_only
	notify_property_list_changed()
	
## @see PROPERTY_USAGE_DEFAULT
func set_usage(property, usage):
	if usage == null:
		_usage.erase(property)
	else:
		_usage[property] = usage
	
func duplicate(deep: bool = false) -> DictionaryObject:
	var dict_obj = DictionaryObject.new(_data.duplicate(deep), _hint.duplicate(deep), _read_only)
	if _origin:
		dict_obj._origin = _origin.duplicate(deep)
	if _update_callback:
		dict_obj._update_callback = _update_callback.duplicate(deep)
	if _custom_display_control:
		dict_obj._custom_display_control = _custom_display_control.duplicate(deep)
	if _duplicate_property:
		dict_obj._duplicate_property = _duplicate_property.duplicate() # 没必要deep
	return dict_obj
	
	
## 用于在检查器界面显示的时候是否只读
func _is_read_only() -> bool:
	return _read_only
	
func _get(property: StringName) -> Variant:
	if _duplicate_property_name.has(property):
		property = _duplicate_property_name[property]
	if _data.has(property):
		return _data[property]
	return null
	
func _set(property: StringName, value: Variant) -> bool:
	if _data.has(property):
		var old_value = _data[property]
		if not _origin.has(property):
			_origin[property] = old_value
		_data[property] = value
		if _update_callback and _update_callback.has(property):
			_update_callback[property].call(value)
			
		value_changed.emit(property, value, old_value)
		return true
	return false
	
func _get_by_index(index: int) -> Variant:
	return _data[__get_index_prop(index)]
	
	
## 获取index位置的属性名称
func __get_index_prop(index) -> String:
	# x表示category、group、subgroup等非数据属性
	# _表示链接属性
	# _data:	[x, a, b, x, x, c, d, x]
	# 加上链接：	[x, _, a, b, _, x, x, c, d, x, _]
	# index：	[ , 0, 1, 2, 3,  ,  , 4, 5,  , 6]
	# 要求 0, 1, 2, 3, 4, 5, 6分别对应的是哪个属性
	
	# 缓存的数据里取
	if _prop_index_cache.has(index):
		return _prop_index_cache[index]
	
	# 连接属性的可以直接给出
	if _duplicate_property.has(index):
		return _duplicate_property[index]
		
	if _prop_index_cache.is_empty():
		_prop_index_cache = _duplicate_property.duplicate()
		
	var arr = [] # 剩余的可分配的index
	for i in _data.size() + _duplicate_property.size():
		if _duplicate_property.has(i):
			continue
		arr.push_back(i)
		
	for key in _data:
		if _is_hidden_prop(key):
			continue
			
		_prop_index_cache[arr.pop_front()] = key
		
	return _prop_index_cache[index]
	
# 前提是index位置的属性是存在的
func _set_by_index(index: int, value: Variant) -> bool:
	return _set(__get_index_prop(index), value)
	
## 增加一条连接属性（占用一个index），但是这个属性实际上是已经存在的某属性。
## 连接属性不会导致_get_property_list()发生变化，
## 只影响_get_by_index和_set_by_index。
func add_duplicate_prop(prop: String) -> void:
	assert(_data.has(prop), "prop [%s] not exist!" % prop)
	var num = 0 # 正常属性的个数
	for key in _data:
		if _is_hidden_prop(key):
			continue
		num += 1
	_duplicate_property[num + _duplicate_property.size()] = prop
	
## @see add_duplicate_prop
func set_duplicate_prop(index: int, prop: String) -> void:
	assert(_data.has(prop), "prop [%s] not exist!" % prop)
	_duplicate_property[index] = prop
	
func _is_hidden_prop(prop: String) -> bool:
	return _usage.has(prop) and (_usage[prop] & PROPERTY_USAGE_CATEGORY or _usage[prop] & PROPERTY_USAGE_GROUP \
		or _usage[prop] & PROPERTY_USAGE_SUBGROUP)
	
func _get_property_list() -> Array[Dictionary]:
	# x表示category、group、subgroup等非数据属性
	# _表示链接属性
	# _data:	[x, a, b, x, x, c, d, x]
	# 加上链接：	[x, _, a, b, _, x, x, c, d, x, _]
	# i：		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	var properties: Array[Dictionary] = []
	var prop_num = {}
	var data_index = 0 # _data游标
	var visible_index = 0 # 可见属性游标
	var props = _data.keys()
	for i in _data.size() + _duplicate_property.size():
		printt("-----------")
		var key
		#if _duplicate_property.has(visible_index):
			#key = _duplicate_property[visible_index]
			#printt(i, "dddddddddd is link prop", key, visible_index)
		#else:
			#
		
		if data_index < props.size() and _is_hidden_prop(props[data_index]):
			key = props[data_index]
			data_index += 1
			printt(i, "ccccccccc is group", key)
		else:
			if _duplicate_property.has(visible_index):
				key = _duplicate_property[visible_index]
				printt(i, "dddddddddd is link prop", key, visible_index)
			else:
				key = props[data_index]
				printt(i, "eeeeeeeeee is normal prop", key, data_index)
				data_index += 1
			visible_index += 1
			
		var info = {
			"name": key,
			"type": _hint[key]["type"] if (_hint.has(key) and _hint[key].has("type")) \
				else (TYPE_NIL if _data[key] == null else typeof(_data[key])),
			"usage": PROPERTY_USAGE_DEFAULT if not _usage.has(key) else _usage[key],
			"hint": PROPERTY_HINT_NONE if not (_hint.has(key) and _hint[key].has("hint")) else _hint[key]["hint"],
			"hint_string": "" if not (_hint.has(key) and _hint[key].has("hint_string")) else _hint[key]["hint_string"]
		}
		
		if prop_num.has(key):
			var new_name = key + "@" + str(prop_num[key]) # TODO 确保这个名称不是_data中本来就存在的
			_duplicate_property_name[new_name] = info["name"]
			info["name"] = new_name
			info["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
			prop_num[key] += 1
		else:
			prop_num[key] = 2
		properties.append(info)
	printt("ggggggg", properties, _data, _hint, _usage, _duplicate_property)
	return properties
	
#由于检查器当前显示的属性不一定是本属性，可能导致revert的对象不是本属性，所以直接屏蔽该功能
#func _property_can_revert(property: StringName) -> bool:
	#return _data.has(property)
#
#func _property_get_revert(property: StringName) -> Variant:
	#if _origin.has(property):
		#return _origin[property]
	#if _data.has(property):
		#return _data[property]
	#return null
	
#func _to_string() -> String:
	#return var_to_str(_data)
	
## 设置一个属性的更新回调函数。当该属性值修改时，调用该函数
func set_update_callback(property: String, callback: Callable) -> void:
	_update_callback[property] = callback
	
## 获取一个属性的更新回调函数。若不存在，返回一个空函数。
func get_update_callback(property: String) -> Callable:
	return _update_callback[property] if _update_callback.has(property) else Callable()
	
## 为某个属性设置自定义显示控件（通过control）。当然，外部也需要相关的逻辑来支持用户设置的自定义控件。
## 如果需要数据和控件进行单、双向绑定，需要用户自行完成绑定逻辑。
## 用户需要充分了解外部可能释放该控件（queue_free），因此需要多加注意。请根据实际情况，是直接使用传入的control还是复制一份再使用。
## property: 属性名称
## control: 自定义显示控件（注意！！！请避免同一个控件被多个DictionaryObject使用，可使用duplicate复制。除非您充分了解自己要干什么。）
## update_callback: 当属性的值发生改变时的回调函数。比如：用户可以利用该函数进行显示控件的更新。
func set_custom_display_control(property: String, control: Control, update_callback: Callable = Callable(), 
	update_immediately: bool = true) -> void:
	_custom_display_control[property] = control
	if update_callback.is_valid():
		set_update_callback(property, update_callback)
		if update_immediately:
			update_callback.call(_get(property))
	
## 获取某个属性的自定义显示控件。如果不存在，则返回null
## 用户需要充分了解外部可能释放该控件（queue_free），因此需要多加注意。
## 如果用户自己对控件进行了复制，那么本方法返回的仍旧是内部记录的控件，而不是用户自行复制的控件。
## 如果需要修改内部记录，请使用get_custom_display_control_duplicate
func get_custom_display_control(property: String) -> Control:
	return _custom_display_control[property] if _custom_display_control.has(property) else null
	
## 获取某个属性的自定义显示控件的新副本。如果不存在，则返回null。
## 每次使用该方法将使内部记录的自定义显示控件被替换为新的副本。
## 调用者需要自行释放原来的控件。
## 所以一些情况下，需要结合get_custom_display_control来使用。
func get_custom_display_control_duplicate(property: String) -> Control:
	if _custom_display_control.has(property) and _custom_display_control[property] != null \
		and _custom_display_control[property] is Control:
		var ret = _custom_display_control[property].duplicate() as Control
		_custom_display_control[property] = ret
		return ret
	return null

func get_modified_value() -> Dictionary:
	var ret = {}
	if _origin:
		for key in _origin:
			if _origin[key] != _data[key]:
				ret[key] = {"new": _data[key], "old": _origin[key]}
	return ret

func get_modified_new_value() -> Dictionary:
	var ret = {}
	if _origin:
		for key in _origin:
			if _origin[key] != _data[key]:
				ret[key] = _data[key]
	return ret
	
## 返回数据对的行字符串形式，比如：a = 1, b = "something"
func get_key_value_line() -> String:
	var arr = []
	for key in _data:
		arr.push_back(key + " = " + var_to_str(_data[key]))
	return ", ".join(arr)
	
func get_keys_line() -> String:
	return ", ".join(_data.keys())
	
func get_values_line() -> String:
	return ", ".join(_data.values().map(func(v): return var_to_str(v)))
