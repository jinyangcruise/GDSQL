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

const FUNCTIONS = ["count", "maxn", "minn", "sum", "avg", "first", "last", 
"grid_checkbox", "ifn", "ifnull"]

static var _instances = {}

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
	_is_real_aggregate_func = true
	_used = true
	return self
	
func count(param):
	if not _empty_data_mode:
		_register("count", param)
	if _preparing:
		return self # 为了运算不报错 比如 select count(1) + 1 from t_user
	if _params.is_empty():
		return 0
	return _params[0].size()
	
func maxn(param):
	if not _empty_data_mode:
		_register("maxn", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		if i > ret:
			ret = i
	_count += 1
	return ret
	
func minn(param):
	if not _empty_data_mode:
		_register("minn", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		if i < ret:
			ret = i
	_count += 1
	return ret
	
func sum(param):
	if not _empty_data_mode:
		_register("sum", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		ret += i
	_count += 1
	return ret
	
func avg(param):
	if not _empty_data_mode:
		_register("avg", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		ret += i
	_count += 1
	return ret / float(_params[_count].size())
	
func first(param):
	if not _empty_data_mode:
		_register("first", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count][0]
	_count += 1
	return ret
	
func last(param):
	if not _empty_data_mode:
		_register("last", param)
	if _preparing:
		return self
	if not _params.has(_count):
		_return_null = true
		return null
	var ret = _params[_count].back()
	_count += 1
	return ret
	
## 元素必须是一个vector2或vector2i，x代表行序号，y代表列序号
## columns: 列数
## rows: 行数
func grid_checkbox(param, columns: int, rows: int):
	if not _empty_data_mode:
		_register("grid_checkbox", param)
	if _preparing:
		return self # 用户也不会拿这个去做运算，所以返回self
	if not _params.has(_count):
		_return_null = true
		return null # 用户也不会拿这个去做运算，所以返回self
	var grid_c = GridContainer.new()
	grid_c.columns = columns
	var is_vector2 = _params[_count][0] is Vector2
	for i in rows:
		for j in columns:
			var cb = CheckBox.new()
			cb.button_pressed = false
			if is_vector2:
				cb.set_meta("pos", Vector2(i, j))
			else:
				cb.set_meta("pos", Vector2i(i, j))
			grid_c.add_child(cb)
	for i in _params[_count]:
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
