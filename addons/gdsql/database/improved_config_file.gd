class_name ImprovedConfigFile
extends ConfigFile

## 如果需要把主键返回，请指定返回到哪个键上
var fill_primary_key: String = ""

## 返回指定小节中所有已定义键标识符的数组。如果该小节不存在，则会引发错误并返回一个空数组。
func get_section_values(section: String, keys: Array = []) -> Dictionary:
	var ret = {}
	if keys.is_empty():
		keys = get_section_keys(section)
	for key in keys:
		ret[key] = get_value(section, key)
		
	# 外部有可能需要主键，把主键返回
	if fill_primary_key != "":
		ret[fill_primary_key] = section
	return ret
	
func set_values(section: String, data: Dictionary):
	for key in data.keys():
		set_value(section, key, data.get(key))
		
func get_all_section_values(keys: Array = []) -> Array[Dictionary]:
	var ret: Array[Dictionary] = []
	for section in get_sections():
		ret.push_back(get_section_values(section, keys))
	return ret
	
## 返回筛选后的数据。筛选规则是，prop==value的数据。num规定了返回多少个匹配的数据。0表示不限制
func filter_values(prop: String, value: Variant, num: int = 0) -> Array[Dictionary]:
	var ret: Array[Dictionary] = []
	var _num = 0
	for section in get_sections():
		if get_value(section, prop) == value:
			ret.push_back(get_section_values(section))
			_num += 1
			if num > 0 and _num >= num:
				break
	return ret
	
## 返回筛选后的第1个数据。筛选规则是，prop==value的数据。num规定了返回多少个匹配的数据。0表示不限制
func filter_first_values(prop: String, value: Variant) -> Dictionary:
	for section in get_sections():
		if get_value(section, prop) == value:
			return get_section_values(section)
	return {}
