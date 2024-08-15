@tool
extends RefCounted
## 聚合函数。一般用于配合BaseDao的group by功能使用。
## evaluate使用AggresiveFunction.get_instance，为每个聚合
## （先进行group by，因为group by不能针对聚合列进行分组）提供一个唯一的
## id，使同一列共享同一个AggresiveFunction.get_instance。但是有个
## 问题，当同一列用了多次聚合函数，会发生错误。比如max(a) + min(b)。
## evaluate_command调用聚合函数时，我们都可以记录调用次数，每次调用都是
## 一个独立的obj。所以我们要把AggresiveFunction设计成每调用一次都用
## 每次对应的空间。但是这就存在一个问题，下一条数据进来的时候，同一列仍要
## 使用同一个AggresiveFunction，但是需要重置调用次数，这样才能根据调用
## 次数找到对应的空间。所以AggresiveFunction要根据“分组-列序号-调用次数”
## 来做hash id。
class_name AggregateFunctions

var id
var _preparing = true ## 准备模式。计算最后一条数据前，需要把它设置成false
var _count = 0 ## 空间序号。比如max(a) + min(b)，计算前者时的_count是0，计算后者时的_count是1
var _methods = {} ## count => method
var _params = {} ## count => param
var _is_real_aggregate_func = false
var _empty_data_mode = false ## 无数据模式
var _used = false ## 该对象的真实聚合函数被至少使用过一次
var _return_null = false ## 真实返回值是否为null。true表示null参与了运算

const FUNCTIONS = ["count", "maxn", "minn", "sum", "avg", "first", "last", "list",
"distinct_group_concat", "group_concat", "grid_checkbox", "ifn", "ifnull"]

static var _instances = {}
#static var regex_comma: RegEx = RegEx.new()

#static func _static_init() -> void:
	#regex_comma.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")

## 重置调用次数
static func recount(p_id):
	get_instance(p_id)._count = 0
	
static func prepare_done(p_id):
	get_instance(p_id)._preparing = false
	
static func enable_empty_data_mode(p_id):
	var obj = get_instance(p_id)
	obj._empty_data_mode = true
	
static func get_instance(p_id) -> AggregateFunctions:
	if not _instances.has(p_id):
		_instances[p_id] = AggregateFunctions.new()
		_instances[p_id].id = p_id
	return _instances[p_id]
	
static func clear_instances():
	_instances.clear()
	
static func possible_has_func(select_name: String) -> bool:
	for i in FUNCTIONS:
		if select_name.contains(i) and select_name.contains("(") and select_name.contains(")"):
			return true
	return false
	
func _register(method: String, param):
	if not _methods.has(_count):
		_methods[_count] = method
		_params[_count] = []
	assert(not param is AggregateFunctions, "Invalid use of group function.")
	_params[_count].push_back(param)
	assert(_methods[_count] == method, "Method not match!")
	_count += 1
	return self
	
func count(param):
	_used = true
	_is_real_aggregate_func = true
	if not _empty_data_mode:
		_register("count", param)
	if _preparing:
		return self # 为了运算不报错 比如 select count(1) + 1 from t_user
	if _params.is_empty():
		return 0
	return _params[0].size()
	
func maxn(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("maxn", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count][0]
	for i in _params[curr_count]:
		if i > ret:
			ret = i
	return ret
	
func minn(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("minn", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count][0]
	for i in _params[curr_count]:
		if i < ret:
			ret = i
	return ret
	
func sum(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("sum", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count][0]
	for i in _params[curr_count]:
		ret += i
	return ret
	
func avg(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("avg", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count][0]
	for i in _params[curr_count]:
		ret += i
	return ret / float(_params[curr_count].size())
	
func first(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("first", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count][0]
	return ret
	
func last(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("last", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = _params[curr_count].back()
	return ret
	
func list(param):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("list", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
	var ret = Array(_params[curr_count])
	return ret
	
## same as: group_concat(distinct id, "+", id order by id separator ':')
func distinct_group_concat(param, separator = ',', order = '', param_0_names = []):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("distinct_group_concat", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
		
	var filtered = _params[curr_count].filter(func(v): return not v == null)
	if filtered.is_empty():
		return null
		
	var list = []
	var order_by = []
	if order == '' or filtered.size() <= 1:
		for i in filtered:
			if not i in list:
				list.push_back(i)
		return separator.join(list.map(func(v):
			for i in v.size():
				v[i] = str(v[i])
			return ''.join(v)))
			
	#var matches = regex_comma.search_all(order)
	var matches = GDSQLUtils.search_symbol(order, ",")
	var arr = []
	if not matches.is_empty():
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var a_order = order.substr(start, i[0] - start).strip_edges()
			arr.push_back(a_order)
			start = i[1]
			
		# 别忘了还有最后一个逗号到最后
		if start < order.length():
			var a_order = order.substr(start).strip_edges()
			arr.push_back(a_order)
	else:
		arr.push_back(order)
	
	for a_order: String in arr:
		a_order = a_order.strip_edges()
		var l = a_order.length()
		var find = false
		if l > 4 and (a_order.contains(" ") or \
		a_order.contains("\t") or a_order.contains("\n")):
			if l > 5:
				if a_order.countn(" desc", l - 5) > 0 or \
				a_order.countn("\tdesc", l - 5) > 0 or \
				a_order.countn("\ndesc", l - 5) > 0:
					order_by.push_back([a_order.substr(0, l - 5).strip_edges(), 1])
					find = true
			if not find:
				if a_order.countn(" asc", l - 4) > 0 or \
				a_order.countn("\tasc", l - 4) > 0 or \
				a_order.countn("\nasc", l - 4) > 0:
					order_by.push_back([a_order.substr(0, l - 4).strip_edges(), 0])
					find = true
		if not find:
			order_by.push_back([a_order, 0])
			
	for a_order_by in order_by:
		var i
		if a_order_by[0] is int:
			i = a_order_by[0]
		elif a_order_by[0].is_valid_int():
			i = int(a_order_by[0]) # user will begin from 1
		else:
			i = param_0_names.find(a_order_by[0]) + 1 # add 1 to be same as the branch above
			
		if i <= 0 or i > param.size():
			push_error("Unknown column '%s' in 'order clause'" % a_order_by[0])
			return null
			
		a_order_by[0] = i - 1
		
	var compare := func(a, b):
		for a_order_by in order_by:
			var v1 = a[a_order_by[0]]
			var v2 = b[a_order_by[0]]
			if v1 == v2:
				continue
			else:
				if a_order_by[1] == 0:
					if v1 == null and v2 != null:
						return true
					if v2 == null and v1 != null:
						return false
					if v1 == null and v2 == null:
						return false
					if v1 < v2:
						return true
					return false
				else:
					if v1 == null and v2 != null:
						return false
					if v2 == null and v1 != null:
						return true
					if v1 == null and v2 == null:
						return false
					if v1 > v2:
						return true
					return false
		return false
		
	for i in filtered:
		if not i in list:
			list.push_back(i)
	list.sort_custom(compare)
	return separator.join(list.map(func(v):
		for i in v.size():
			v[i] = str(v[i])
		return ''.join(v)))
	
## support: group_concat(id)
## support: group_concat(id separator ':') => group_concat(id, ':')
## support: group_concat(id order by id) => group_concat(id, ',', 'id')
## support: group_concat(id order by id desc separator ':') => group_concat(id, ':', 'id desc')
## support: group_concat(id, "+", uid order by sid asc separator ':') => 
##          group_concat(id + "+" + uid, ':', 'id desc')
## support: group_concat(distinct id, "+", uid order by sid asc separator ':') => 
##          distinct_group_concat(id + "+" + uid, ':', 'id asc')
func group_concat(param, separator = ',', order = '', param_0_names = []):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("group_concat", param)
	if _preparing:
		return self
	if not _params.has(curr_count):
		_return_null = true
		return null
		
	var filtered = _params[curr_count].filter(func(v): return not v == null)
	if filtered.is_empty():
		return null
		
	var order_by = []
	if order == '' or filtered.size() <= 1:
		return separator.join(filtered.map(func(v):
			for i in v.size():
				v[i] = str(v[i])
			return ''.join(v)))
		
	#var matches = regex_comma.search_all(order)
	var matches = GDSQLUtils.search_symbol(order, ",")
	var arr = []
	if not matches.is_empty():
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var a_order = order.substr(start, i[0] - start).strip_edges()
			arr.push_back(a_order)
			start = i[1]
			
		# 别忘了还有最后一个逗号到最后
		if start < order.length():
			var a_order = order.substr(start).strip_edges()
			arr.push_back(a_order)
	else:
		arr.push_back(order)
		
	for a_order: String in arr:
		a_order = a_order.strip_edges()
		var l = a_order.length()
		var find = false
		if l > 4 and (a_order.contains(" ") or \
		a_order.contains("\t") or a_order.contains("\n")):
			if l > 5:
				if a_order.countn(" desc", l - 5) > 0 or \
				a_order.countn("\tdesc", l - 5) > 0 or \
				a_order.countn("\ndesc", l - 5) > 0:
					order_by.push_back([a_order.substr(0, l - 5).strip_edges(), 1])
					find = true
			if not find:
				if a_order.countn(" asc", l - 4) > 0 or \
				a_order.countn("\tasc", l - 4) > 0 or \
				a_order.countn("\nasc", l - 4) > 0:
					order_by.push_back([a_order.substr(0, l - 4).strip_edges(), 0])
					find = true
		if not find:
			order_by.push_back([a_order, 0])
		
	for a_order_by in order_by:
		var i
		if a_order_by[0].is_valid_int():
			i = int(a_order_by[0]) # user will begin from 1
		else:
			i = param_0_names.find(a_order_by[0]) + 1 # add 1 to be same as the branch above
			
		if i <= 0 or i > param.size():
			push_error("Unknown column '%s' in 'order clause'" % a_order_by[0])
			return null
			
		a_order_by[0] = i - 1
		
	var compare := func(a, b):
		for a_order_by in order_by:
			var v1 = a[a_order_by[0]]
			var v2 = b[a_order_by[0]]
			if v1 == v2:
				continue
			else:
				if a_order_by[1] == 0:
					if v1 == null and v2 != null:
						return true
					if v2 == null and v1 != null:
						return false
					if v1 == null and v2 == null:
						return false
					if v1 < v2:
						return true
					return false
				else:
					if v1 == null and v2 != null:
						return false
					if v2 == null and v1 != null:
						return true
					if v1 == null and v2 == null:
						return false
					if v1 > v2:
						return true
					return false
		return false
		
	filtered.sort_custom(compare)
	return separator.join(filtered.map(func(v):
		for i in v.size():
			v[i] = str(v[i])
		return ''.join(v)))
	
## 元素必须是一个vector2或vector2i，x代表行序号，y代表列序号
## columns: 列数
## rows: 行数
func grid_checkbox(param, columns: int, rows: int):
	_used = true
	_is_real_aggregate_func = true
	var curr_count = _count
	if not _empty_data_mode:
		_register("grid_checkbox", param)
	if _preparing:
		return self # 用户也不会拿这个去做运算，所以返回self
	if not _params.has(curr_count):
		_return_null = true
		return null # 用户也不会拿这个去做运算，所以返回self
	var grid_c = GridContainer.new()
	grid_c.add_theme_constant_override("h_separation", 1)
	grid_c.add_theme_constant_override("v_separation", 1)
	grid_c.columns = columns
	var is_vector2 = _params[curr_count][0] is Vector2
	var sb = StyleBoxFlat.new()
	sb.set_border_width_all(1)
	sb.border_color = Color.WHITE
	sb.set_content_margin_all(0)
	sb.draw_center = false
	var sb_center = sb.duplicate(true)
	sb_center.draw_center = true
	sb_center.border_color = Color.GREEN
	for i in rows:
		for j in columns:
			var cb = CheckBox.new()
			if i == floor(columns/2) and j == floor(rows/2):
				cb.add_theme_stylebox_override("normal", sb_center)
				cb.add_theme_stylebox_override("pressed", sb_center)
				cb.add_theme_stylebox_override("hover", sb_center)
			else:
				cb.add_theme_stylebox_override("normal", sb)
				cb.add_theme_stylebox_override("pressed", sb)
				cb.add_theme_stylebox_override("hover", sb)
			cb.button_pressed = false
			if is_vector2:
				cb.set_meta("pos", Vector2(i, j))
			else:
				cb.set_meta("pos", Vector2i(i, j))
			grid_c.add_child(cb)
	for i in _params[curr_count]:
		if i:
			var idx = i.x * rows + i.y
			var cb = grid_c.get_child(idx) as CheckBox
			cb.button_pressed = true
	return grid_c
	
# NOTICE 非聚合函数，不register
func ifn(condition, value_if_true, value_if_false):
	if condition is AggregateFunctions or value_if_true is AggregateFunctions or value_if_false is AggregateFunctions:
		#assert(_preparing, "Inner error 330.")
		return self # self中必定包含了condition、value_if_true、value_if_false，如果它们是AggregateFunctions的话
	return value_if_true if condition else value_if_false
	
# NOTICE 非聚合函数，不register
func ifnull(value, value_if_null):
	if value is AggregateFunctions or value_if_null is AggregateFunctions:
		return self
	return value_if_null if typeof(value) == TYPE_NIL else value
