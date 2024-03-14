@tool
extends RefCounted
class_name ConditionWrapper

static var regex_1: RegEx
static var regex_2: RegEx
static var regex_3: RegEx

var _cond: String
var _and_wrapper: ConditionWrapper
var _or_wrapper: ConditionWrapper

static func _static_init() -> void:
	# 匹配xxx.yyy这种格式，并且不在双引号内
	regex_1 = RegEx.new()
	regex_1.compile("([0-9a-zA-Z_]+)\\.([0-9a-zA-Z_]+)(?=([^\\\"]*\\\"[^\\\"]*\\\")*[^\\\"]*$)")
	
	# 匹配xxx.yyy这种格式，并且不在单引号内
	regex_2 = RegEx.new()
	regex_2.compile("([0-9a-zA-Z_]+)\\.([0-9a-zA-Z_]+)(?=([^\']*\'[^\']*\')*[^\']*$)")
	
	# 匹配xxx.yyy这种格式，并且不是xxx.yyy(这种格式
	regex_3 = RegEx.new()
	regex_3.compile("([0-9a-zA-Z_]+\\.[0-9a-zA-Z_\\-]+)(\\s)*\\(")
	
## 可以把a.b修改为a["b"]
static func modify_dot_to_get(a_str: String) -> String:
	# dictionary不支持点号取值,所以要改成方括号取值或get取值
	# 没匹配到的也不会被替换，所以统一逻辑
	var arr_1 = regex_1.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(), m.get_string()])
	var arr_2 = regex_2.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(), m.get_string()]) if !arr_1.is_empty() else []
	var arr_3 = regex_3.search_all(a_str).map(func(m): return "%d.%s" % [m.get_start(1), m.get_string(1)]) if (!arr_1.is_empty()) and (!arr_2.is_empty()) else []

	# 要处理的是arr_1和arr_2的交集，然后再排除掉arr_3之后剩余的元素
	var valid = arr_1.filter(func(e): return arr_2.has(e)).filter(func(e): return !arr_3.has(e))

	# 根据起始位置，修改原字符串
	var offset = 0 # 修改过程中增加的字符长度
	for i in valid:
		var s = i.split(".") # 得到诸如此形式：[22, "a", "level"]
		var pre = a_str.substr(0, int(s[0]) + offset)
		var modify = s[1] + "[\"" + s[2] + "\"]"
		var post = a_str.substr(pre.length() + s[1].length() + s[2].length() + 1) 
		a_str = pre + modify + post
		offset += 3 # 一对中括号+一对引号-一个点号=3
		
	return a_str

## 设置条件
## a_cond：条件，比如：age >= 20，比如：a.id == b.id
func cond(a_cond: String) -> ConditionWrapper:
	_cond = a_cond
	return self
	
## 对条件进行判定
## datas: 包含判定所需要的数据，键是表名或别名，值是该表对应的一条数据
func check(datas: Dictionary):
	# 需要check自身以及and、or的条件
	var ret = true
	if _cond:
		var variable_names = []
		var variable_values = []
		
		var is_single_table = datas.size() == 1 # 该行数据只有一个表的意思
		for key in datas:
			variable_names.push_back(key)
			variable_values.push_back(datas[key])
			_cond = ConditionWrapper.modify_dot_to_get(_cond)
			
			# 还要考虑field不是用的t.xxx而是直接用的xxx的结构该怎么办
			# 联表时一般select的字段习惯上都会使用`别名.字段`这种形式，所以只考虑单表的情况
			# 单表查询，我们除了按dictionary传给variable_names，也按每个字段传给variable_names
			# 但是还是有缺点，就是字段名称和表别名重名了（概率小），另一个就是字段名称使用了Godot函数名称，导致函数名称被替换了（用户需要注意）
			if is_single_table:
				for f in datas[key]:
					variable_names.push_back(f) # 祈祷字段名称和表名以及用户使用的函数名称不一样吧……
					variable_values.push_back(datas[key][f])
			
		ret = GDSQLWorkbenchManagerClass.evaluate_command(null, _cond, variable_names, variable_values)
		
	# and / or
	if _and_wrapper:
		if !ret:
			return false
		return _and_wrapper.check(datas)
		
	if _or_wrapper:
		if ret:
			return true
		return _or_wrapper.check(datas)
		
	return ret
	
## 与
func and_(wrapper: ConditionWrapper) -> ConditionWrapper:
	assert(_and_wrapper == null, "already set an `add` wrapper")
	assert(_or_wrapper == null, "already set an `or` wrapper")
	_and_wrapper = wrapper
	return self
	
## 或
func or_(wrapper: ConditionWrapper) -> ConditionWrapper:
	assert(_and_wrapper == null, "already set an `add` wrapper")
	assert(_or_wrapper == null, "already set an `or` wrapper")
	_or_wrapper = wrapper
	return self
