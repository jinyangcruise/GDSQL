@tool
extends RefCounted
class_name ConditionWrapper

#static var regex_1: RegEx
#static var regex_2: RegEx
#static var regex_3: RegEx

var _cond: String
var _sql_input_names: Dictionary
var _nested_query: Dictionary
var _and_wrapper: ConditionWrapper
var _or_wrapper: ConditionWrapper
var _lacking_tables: Array

#static func _static_init() -> void:
	## 匹配xxx.yyy这种格式，并且不在双引号内
	#regex_1 = RegEx.new()
	#regex_1.compile("([0-9a-zA-Z_]+)\\.([0-9a-zA-Z_]+)(?=([^\\\"]*\\\"[^\\\"]*\\\")*[^\\\"]*$)")
	#
	## 匹配xxx.yyy这种格式，并且不在单引号内
	#regex_2 = RegEx.new()
	#regex_2.compile("([0-9a-zA-Z_]+)\\.([0-9a-zA-Z_]+)(?=([^\']*\'[^\']*\')*[^\']*$)")
	#
	## 匹配xxx.yyy这种格式，并且不是xxx.yyy(这种格式
	#regex_3 = RegEx.new()
	#regex_3.compile("([0-9a-zA-Z_]+\\.[0-9a-zA-Z_\\-]+)(\\s)*\\(")
	
## NOTICE dictionary 支持点号取值，所以有点多余了
## 可以把a.b修改为a["b"]
#static func modify_dot_to_get(a_str: String) -> String:
	## dictionary不支持点号取值,所以要改成方括号取值或get取值
	## 没匹配到的也不会被替换，所以统一逻辑
	#var arr_1 = regex_1.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(), m.get_string()])
	#var arr_2 = regex_2.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(), m.get_string()]) if !arr_1.is_empty() else []
	#var arr_3 = regex_3.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(1), m.get_string(1)]) if (!arr_1.is_empty()) and (!arr_2.is_empty()) else []
#
	## 要处理的是arr_1和arr_2的交集，然后再排除掉arr_3之后剩余的元素
	#var valid = arr_1.filter(func(e): return arr_2.has(e)).filter(func(e): return !arr_3.has(e))
	#
	## 根据起始位置，修改原字符串
	#var offset = 0 # 修改过程中增加的字符长度
	#for i in valid:
		#var s = i.split(".") # 得到诸如此形式：[22, "a", "level"]
		#var pre = a_str.substr(0, int(s[0]) + offset)
		#var modify = s[1] + "[\"" + s[2] + "\"]"
		#var post = a_str.substr(pre.length() + s[1].length() + s[2].length() + 1) 
		#a_str = pre + modify + post
		#offset += 3 # 一对中括号+一对引号-一个点号=3
		#
	#return a_str

## 设置条件
## a_cond：条件，比如：age >= 20，比如：a.id == b.id
func cond(a_cond: String, sql_input_names: Dictionary = {}, nested_query: Dictionary = {}) -> ConditionWrapper:
	_cond = a_cond
	_sql_input_names = sql_input_names
	_nested_query.clear()
	_nested_query.merge(nested_query, true)
	return self
	
## 对条件进行判定
## static_inputs：固定的补充表的数据
## varying_inputs：每条数据，键是表名或别名，值是该表对应的一条数据）
func check(static_inputs: Array, varying_inputs: Dictionary):
	# 需要check自身以及and、or的条件
	var ret = true
	if _cond:
		ret = GDSQLUtils.evaluate_command_with_sql_expression(null, _cond, 
			[], [], _sql_input_names, static_inputs, varying_inputs, 
			_nested_query, _lacking_tables)
		if not _lacking_tables.is_empty():
			return null
			
		if ret is QueryResult:
			var rows = ret.get_data()
			if rows.is_empty():
				ret = false
			elif rows.size() > 1:
				assert(false, "Subquery [%s] returns more than 1 row." % _cond)
				return null
			elif rows[0].size() > 1:
				assert(false, "Subquery [%s] returns more than 1 column." % _cond)
				return null
			else:
				ret = bool(rows[0][0])
				
	# and / or
	if _and_wrapper:
		if !ret:
			return false
		ret = _and_wrapper.check(static_inputs, varying_inputs)
		if not _and_wrapper.get_lacking_tables().is_empty():
			_lacking_tables.append_array(_and_wrapper.get_lacking_tables())
		return ret
		
	if _or_wrapper:
		if ret:
			return true
		ret = _or_wrapper.check(static_inputs, varying_inputs)
		if not _or_wrapper.get_lacking_tables().is_empty():
			_lacking_tables.append_array(_or_wrapper.get_lacking_tables())
		return ret
		
	return ret
	
## 与
func and_(wrapper: ConditionWrapper) -> ConditionWrapper:
	if _and_wrapper != null:
		assert(false, "already set an `add` wrapper")
		return null
	if _or_wrapper != null:
		assert(false, "already set an `or` wrapper")
		return null
	_and_wrapper = wrapper
	return self
	
## 或
func or_(wrapper: ConditionWrapper) -> ConditionWrapper:
	if _and_wrapper != null:
		assert(false, "already set an `add` wrapper")
		return null
	if _or_wrapper != null:
		assert(false, "already set an `or` wrapper")
		return null
	_or_wrapper = wrapper
	return self
	
## 缺少的表
func get_lacking_tables():
	return _lacking_tables
