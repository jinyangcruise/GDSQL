extends RefCounted

signal value_changed(prop: StringName, new_value: Variant, old_value: Variant)

var _origin: Dictionary
var _data: Dictionary
var _hint: Dictionary
var _usage: Dictionary
var _update_callback: Dictionary
var _custom_display_control: Dictionary
var _read_only: bool
## 连接属性
var _duplicate_property: Array

## data： 一个key-value形成的字典数据。或一个长度为2的数组，第一个元素是key的一维数组，第二个元素是value的一维数组
## hint： 一个key-dictionary字典数据。key为data中的key，dictionary为包含"hint"和"hint_string"，"link"，"usage"，"type"键的数据。@see PropertyHint 
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
	for key in hint:
		if hint[key].has("link"):
			_data[key] = hint[key]["link"]
			_duplicate_property.push_back(key)
		if hint[key].has("usage"):
			_usage[key] = hint[key]["usage"]
			
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
	
func get_prop_type(prop: String) -> int:
	return _hint[prop]["type"] if (_hint.has(prop) and _hint[prop].has("type")) \
		else (TYPE_NIL if _data[prop] == null else typeof(_data[prop]))
		
func get_prop_type_by_index(index: int) -> int:
	var prop = __get_index_prop(index)
	return _hint[prop]["type"] if (_hint.has(prop) and _hint[prop].has("type")) \
		else (TYPE_NIL if _data[prop] == null else typeof(_data[prop]))
		
func get_prop_usage(prop: String) -> int:
	var usage = PROPERTY_USAGE_DEFAULT if not _usage.has(prop) else _usage[prop]
	if _duplicate_property.has(prop):
		usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	return usage
	
func get_prop_usage_by_index(index: int) -> int:
	var prop = __get_index_prop(index)
	return get_prop_usage(prop)
	
func get_visible_data() -> Dictionary:
	var ret = {}
	for key in _data:
		if not _is_hidden_prop(key):
			ret[key] = _data[key]
	return ret
	
func reset_data(data, hint = null):
	_usage = {}
	_duplicate_property = []
	if data is Dictionary:
		_data = data
	elif data is Array and data.size() == 2 and data[0] is Array and data[1] is Array:
		_data = {}
		for i in data[0].size():
			_data[data[0][i]] = data[1][i]
	if hint != null:
		_hint = hint
		for key in hint:
			if hint[key].has("link"):
				_data[key] = hint[key]["link"]
				_duplicate_property.push_back(key)
			if hint[key].has("usage"):
				_usage[key] = hint[key]["usage"]
	notify_property_list_changed()
	
## 提交：将目前修改过的值全部标记为非修改状态
func commit() -> void:
	if _origin:
		_origin.clear()
		
## 回滚：
func revert():
	if _origin:
		for k in _origin:
			_set(k, _origin[k])
		_origin.clear()
	
func reset_hint(hint: Dictionary):
	_hint = hint
	notify_property_list_changed()
	
func reset_read_only(read_only: bool):
	_read_only = read_only
	notify_property_list_changed()
	
func duplicate(deep: bool = false) -> GDSQL.DictionaryObject:
	var dict_obj = GDSQL.DictionaryObject.new(_data.duplicate(deep), _hint.duplicate(deep), _read_only)
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
	if _duplicate_property.has(property):
		property = _data[property]
	if _data.has(property):
		return _data[property]
	return null
	
## 设置属性的值。默认情况下如果值无变化，则不会触发value_changed信号，除非force为true。
func _set(property: StringName, value: Variant, force: bool = false) -> bool:
	if _duplicate_property.has(property):
		property = _data[property]
	if _data.has(property):
		var old_value = _data[property]
		if typeof(value) == typeof(old_value) and value == old_value and not force:
			return true
		if not _origin.has(property):
			_origin[property] = old_value
		_data[property] = value
		if _update_callback and _update_callback.has(property):
			_update_callback[property].call(value)
			
		value_changed.emit(property, value, old_value)
		# 连接属性也发出信号
		for i in _duplicate_property:
			if _data[i] == property:
				value_changed.emit(i, value, old_value)
		return true
	return false
	
func _get_by_index(index: int) -> Variant:
	return _get(__get_index_prop(index))
	
	
## 获取index位置的属性名称。对于连接属性，key也必须存在于_data中。
func __get_index_prop(index) -> String:
	var i = 0
	for key in _data:
		if _is_hidden_prop(key):
			continue
		if i == index:
			return key
		i += 1
	return ""
	
# 前提是index位置的属性是存在的
func _set_by_index(index: int, value: Variant) -> bool:
	return _set(__get_index_prop(index), value)
	
# 把index属性设置为同类型变量的默认值
func _set_default_by_index(index:int) -> bool:
	var prop = __get_index_prop(index)
	if _duplicate_property.has(prop):
		prop = _data[prop]
		
	var type = _hint[prop]["type"] if (_hint.has(prop) and _hint[prop].has("type")) \
		else (TYPE_NIL if _data[prop] == null else typeof(_data[prop]))
	return _set(prop, GDSQL.DataTypeDef.DEFUALT_VALUES[type])
	
## 设置属性为链接属性，链接属性的值指向到被链接的属性的值。
## 被链接属性的名称可以从_hint[链接属性]["link"]获取到。
## 请勿嵌套链接。
## 还有一种设置链接属性的方法，就是在hint中设置"link"为true。
func mark_link_prop(prop: String, src_prop: String) -> void:
	if not _data.has(prop):
		assert(false, "prop [%s] not exist!" % prop)
		return
	if not _data.has(_data[prop]):
		assert(false, "prop [%s] value is not a prop")
		return
	_data[prop] = src_prop
	_duplicate_property.push_back(prop)
	
func _is_hidden_prop(prop: String) -> bool:
	return _usage.has(prop) and (_usage[prop] & PROPERTY_USAGE_CATEGORY or _usage[prop] & PROPERTY_USAGE_GROUP \
		or _usage[prop] & PROPERTY_USAGE_SUBGROUP)
		
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	for key in _data:
		var key_bak = key
		var usage = PROPERTY_USAGE_DEFAULT if not _usage.has(key) else _usage[key]
		if _duplicate_property.has(key):
			key = _data[key]
			usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
			
		var info = {
			"name": key if key == key_bak else key_bak,
			"type": _hint[key]["type"] if (_hint.has(key) and _hint[key].has("type")) \
				else (TYPE_NIL if _data[key] == null else typeof(_data[key])),
			"usage": usage,
			"hint": PROPERTY_HINT_NONE if not (_hint.has(key) and _hint[key].has("hint")) else _hint[key]["hint"],
			"hint_string": "" if not (_hint.has(key) and _hint[key].has("hint_string")) else _hint[key]["hint_string"]
		}
		
		# 可能需要从数据库提供字典值
		if info["hint"] == PROPERTY_HINT_ENUM or info["hint"] == PROPERTY_HINT_ENUM_SUGGESTION:
			# 字符串的enum没有办法进行更多提示
			if info.type == TYPE_STRING:
				var arr = (info["hint_string"] as String).rsplit(":", true, 1)
				if arr.size() == 2 and (arr[0] as String).is_absolute_path():
					var conf = GDSQL.ConfManager.get_conf(arr[0], "")
					if conf:
						info["hint_string"] = ",".join(conf.get_all_section_value(arr[1]))
					else:
						push_error("Can not load file [%s]" % arr[0])
			elif info.type == TYPE_INT:
				var arr = (info["hint_string"] as String).rsplit(":", true, 2)
				if arr.size() == 3 and (arr[0] as String).is_absolute_path():
					var meta_key = info.name.to_snake_case() + "_enum_hint_string_dict"
					if has_meta(meta_key):
						info["hint_string"] = get_meta(meta_key)
					else:
						var conf = GDSQL.ConfManager.get_conf(arr[0], "")
						if conf:
							info["hint_string"] = ",".join(
								conf.get_all_section_values([arr[1], arr[2]]).map(func(v):
									return str(v[arr[2]]) + ":" + str(v[arr[1]])))
							set_meta(meta_key, info.hint_string)
						else:
							push_error("Can not load file [%s]" % arr[0])
							
		properties.append(info)
		
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
## control: 自定义显示控件（注意！！！请避免同一个控件被多个GDSQL.DictionaryObject使用，可使用duplicate复制。除非您充分了解自己要干什么。）
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
	if _custom_display_control.has(property) and _custom_display_control[property] \
		and _custom_display_control[property] is Control:
		var ret = _custom_display_control[property].duplicate() as Control
		_custom_display_control[property] = ret
		return ret
	return null
	
func free_custom_display_control(property: String) -> void:
	var ctl = get_custom_display_control(property)
	if ctl:
		ctl.queue_free()
		_custom_display_control.erase(property)
		
func free_all_custom_display_controls() -> void:
	for p in _custom_display_control:
		(_custom_display_control[p] as Control).queue_free()
	_custom_display_control.clear()

func get_modified_value() -> Dictionary:
	var ret = {}
	if _origin:
		for key in _origin:
			if typeof(_origin[key]) != typeof(_data[key]) or _origin[key] != _data[key]:
				ret[key] = {"new": _data[key], "old": _origin[key]}
	return ret

func get_modified_new_value() -> Dictionary:
	var ret = {}
	if _origin:
		for key in _origin:
			if typeof(_origin[key]) != typeof(_data[key]) or _origin[key] != _data[key]:
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
