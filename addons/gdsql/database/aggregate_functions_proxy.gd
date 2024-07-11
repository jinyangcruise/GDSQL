@tool
## 聚合函数对象代理
extends RefCounted
class_name AggregateFunctionsProxy

## 这个名字尽最大可能不与用户的字段名重复
var ______________agg_func_obj: AggregateFunctions

func _init(hash_id) -> void:
	______________agg_func_obj = AggregateFunctions.get_instance(hash_id)
	
func count(param):
	return ______________agg_func_obj.count(param)
	
func maxn(param):
	return ______________agg_func_obj.maxn(param)
	
func minn(param):
	return ______________agg_func_obj.minn(param)
	
func sum(param):
	return ______________agg_func_obj.sum(param)
	
func avg(param):
	return ______________agg_func_obj.avg(param)
	
func first(param):
	return ______________agg_func_obj.first(param)
	
func last(param):
	return ______________agg_func_obj.last(param)
	
func grid_checkbox(param, columns: int, rows: int):
	return ______________agg_func_obj.grid_checkbox(param, columns, rows)
	
func ifn(condition, value_if_true, value_if_false):
	return ______________agg_func_obj.ifn(condition, value_if_true, value_if_false)
	
func ifnull(value, value_if_null):
	return ______________agg_func_obj.ifnull(value, value_if_null)
