extends RefCounted
class_name QueryResult

var _err = OK
var _affected_rows = 0
var _warnings
var _data
var _last_insert_id = 0
var _has_head = true
## 自增键的值插入后记录一下
var _generated_keys = {}
var _cost_time: float

func ok() -> bool:
	return _err is int and _err == OK
	
func get_err():
	return _err
	
func get_affected_rows() -> int:
	return _affected_rows
	
func get_warnings() -> Array:
	return [] if _warnings == null else _warnings
	
## 获取query后的表头和数据
func get_head_and_data() -> Array:
	return [] if _data == null else _data
	
## 获取query后的数据，不包括表头
func get_data() -> Array:
	if not _has_head:
		return get_head_and_data()
	if _data is Array and _data.size() > 1:
		return (_data as Array).slice(1)
	return []
	
## 获取query后的数据的表头
func get_head() -> Array:
	if not _has_head:
		return []
	if _data is Array and _data.size() > 0:
		return (_data as Array)[0]
	return []
	
## 获取query后的数据的原始格式。请注意，ConigFile存储的数据在底层经过了var_to_str。
## 例如，一张图片会被存储为Resource("res://xxx.png")，常规get_data时，ConfigFile将自动
## 解析这个资源成为一张图片。很多数据类型与此同理。因此，增加了本方法供用户获取到文本形式的数据，
## 从而让用户能拿到诸如【Resource("res://xxx.png")】格式（而不是一张图片）的数据。
func get_raw() -> Array:
	if _data == null: return []
	var ret = []
	var head = true # 表头不做处理
	for arr in _data:
		var a = []
		for i in arr:
			if head:
				a.push_back(i)
			else:
				a.push_back(var_to_str(i))
		head = false
		ret.push_back(a)
	return ret
	
func get_last_insert_id():
	return _last_insert_id
	
func get_generated_keys() -> Dictionary:
	return _generated_keys
	
func get_cost_time() -> float:
	return _cost_time
