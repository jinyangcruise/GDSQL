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
var _preparing = true
var _count = 0
var _methods = {} # count => method
var _params = {} # count => param
var _is_real_aggregate_func = false

const FUNCTIONS = ["count", "maxn", "minn", "sum", "avg", "first", "last", 
"grid_checkbox", "ifn", "ifnull"]

static var _instances = {}

## 重置调用次数
static func recount(id):
	get_instance(id)._count = 0
	
static func prepare_done(id):
	get_instance(id)._preparing = false
	
static func get_instance(id) -> AggregateFunctions:
	if not _instances.has(id):
		_instances[id] = AggregateFunctions.new()
		_instances[id].id = id
	return _instances[id]
	
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
	return self
	
func count(param):
	_register("count", param)
	if _preparing:
		return self
	return _methods[0].size()
	
func maxn(param):
	_register("maxn", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		if i > ret:
			ret = i
	_count += 1
	return ret
	
func minn(param):
	_register("minn", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		if i < ret:
			ret = i
	_count += 1
	return ret
	
func sum(param):
	_register("sum", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		ret += i
	_count += 1
	return ret
	
func avg(param):
	_register("avg", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count][0]
	for i in _params[_count]:
		ret += i
	_count += 1
	return ret / float(_params[_count].size())
	
func first(param):
	_register("first", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count][0]
	_count += 1
	return ret
	
func last(param):
	_register("last", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
	var ret = _params[_count].back()
	_count += 1
	return ret
	
## 元素必须是一个vector2或vector2i，x代表行序号，y代表列序号
## columns: 列数
## rows: 行数
func grid_checkbox(param, columns: int, rows: int):
	_register("grid_checkbox", param)
	if _preparing:
		return self
	if not _params.has(_count):
		return null
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
		assert(_preparing, "Inner error 330.")
		return self # self中必定包含了condition、value_if_true、value_if_false，如果它们是AggregateFunctions的话
	return value_if_true if condition else value_if_false
	
# NOTICE 非聚合函数，不register
func ifnull(value, value_if_null):
	if value is AggregateFunctions or value_if_null is AggregateFunctions:
		assert(_preparing, "Inner error 331.")
		return self
	return value_if_null if typeof(value) == TYPE_NIL else value
