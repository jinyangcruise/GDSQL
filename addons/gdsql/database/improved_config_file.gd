class_name ImprovedConfigFile
extends ConfigFile

## 如果需要把主键返回，请指定返回到哪个键上
var fill_primary_key: String = ""

## 索引的数据
## {column_name: {column_value: [section1, section2, section3...]}}
var indexed_datas: Dictionary

## 返回指定小节中所有已定义键标识符的数组。如果该小节不存在，则会引发错误并返回一个空数组。
func get_section_values(section: String, keys: Array = []) -> Dictionary:
	var ret = {}
	if keys.is_empty():
		keys = get_section_keys(section)
	for key in keys:
		ret[key] = _get_value(section, key)
		
	# 外部有可能需要主键，把主键返回
	if fill_primary_key != "":
		ret[fill_primary_key] = section
	return ret
	
func set_values(section: String, data: Dictionary):
	for key in data.keys():
		_set_value(section, key, data.get(key))
		
func get_all_section_values(keys: Array = []) -> Array[Dictionary]:
	var ret: Array[Dictionary] = []
	for section in get_sections():
		ret.push_back(get_section_values(section, keys))
	return ret
	
func get_all_section_value(key: String) -> Array:
	var ret = []
	for section in get_sections():
		ret.push_back(_get_value(section, key))
	return ret
	
## 返回筛选后的数据。筛选规则是，prop==value的数据。num规定了返回多少个匹配的数据。0表示不限制
func filter_values(prop: String, value: Variant, num: int = 0) -> Array[Dictionary]:
	var ret: Array[Dictionary] = []
	var _num = 0
	for section in get_sections():
		if _get_value(section, prop) == value:
			ret.push_back(get_section_values(section))
			_num += 1
			if num > 0 and _num >= num:
				break
	return ret
	
## 返回筛选后的第1个数据。筛选规则是，prop==value的数据。num规定了返回多少个匹配的数据。0表示不限制
func filter_first_values(prop: String, value: Variant) -> Dictionary:
	for section in get_sections():
		if _get_value(section, prop) == value:
			return get_section_values(section)
	return {}
	
func set_indexed_props(props: Array):
	if props == indexed_datas.keys():
		return
	indexed_datas.clear()
	if props.is_empty():
		return
	var sections = get_sections()
	for p in props:
		indexed_datas[p] = {}
		for section in sections:
			var p_value = _get_value(section, p)
			if not indexed_datas[p].has(p_value):
				indexed_datas[p][p_value] = []
			indexed_datas[p][p_value].push_back(section)
			
func _erase_section(section: String):
	# 删除索引里的该数据
	if has_section(section):
		for p in indexed_datas:
			var p_value = _get_value(section, p)
			indexed_datas[p][p_value].erase(section)
			
	erase_section(section)
	
func _get_value(seciton: String, key: String, default = null):
	if has_section_key(seciton, key):
		return get_value(seciton, key, default)
	return default
	
func _set_value(section: String, key: String, value: Variant):
	# 修改索引里的该数据
	if has_section(section):
		# 如果key是索引列
		if key in indexed_datas:
			if has_section_key(section, key):
				var old_value = _get_value(section, key)
				if old_value != value:
					indexed_datas[key][old_value].erase(section)
					indexed_datas[key][value].push_back(section)
			# 表里还没插入该字段
			else:
				if not indexed_datas[key].has(value):
					indexed_datas[key][value] = []
				indexed_datas[key][value].push_back(section)
	else:
		if value != null:
			if key in indexed_datas:
				if not indexed_datas[key].has(value):
					indexed_datas[key][value] = []
				indexed_datas[key][value].push_back(section)
				
	set_value(section, key, value)
	
func _clear():
	indexed_datas.clear()
	clear()
	
func get_all_section_values_by_indexed_key(indexed_name: String) -> Array[Dictionary]:
	var p_value_sections = indexed_datas[indexed_name]
	var ret: Array[Dictionary] = []
	var keys = null
	for p_value in p_value_sections:
		for section in p_value_sections[p_value]:
			if keys == null:
				keys = get_section_keys(section)
			var a_data = {}
			for k in keys:
				a_data[k] = _get_value(section, k)
			ret.push_back(a_data)
	return ret
	
func get_sections_by_indexed_key(indexed_name: String, indexed_value) -> Array:
	if indexed_datas[indexed_name].has(indexed_value):
		return indexed_datas[indexed_name][indexed_value].duplicate()
	return []
