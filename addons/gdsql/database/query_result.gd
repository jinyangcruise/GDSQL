extends RefCounted
class_name QueryResult

var _err = OK
var _affected_rows = 0
var _warnings
var _data
var _last_insert_id = 0
var _columns_count = 0
var _has_head = true
## 自增键的值插入后记录一下
var _generated_keys = {}
var _cost_time: float
var _lack_tables

func lack_data() -> bool:
	return _lack_tables != null
	
func get_lack_tables() -> Array:
	return _lack_tables if _lack_tables != null else []
	
func ok() -> bool:
	return _err is int and _err == OK
	
func get_err():
	return _err
	
func get_affected_rows() -> int:
	return _affected_rows
	
func get_warnings() -> Array:
	return [] if _warnings == null else _warnings
	
func get_columns_count() -> int:
	return _columns_count
	
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
	
## 获取query后的数据的第一条数据，可以指定只返回某一列和空数据集时的返回值
func get_first_row(col_index = null, default = null):
	assert(col_index == null or col_index is int, "Invalid col_index type: %s" % typeof(col_index))
	var ret = get_data()
	if ret.is_empty():
		return default
	if col_index == null:
		return ret[0]
	assert(ret[0].size() > col_index, "Invalid col_index: %s" % col_index)
	return ret[0][col_index]
	
## 获取query后的数据的某列数据，可以指定空数据集时的返回值
func get_column(col_index = 0, default = null):
	var ret = get_data()
	if ret.is_empty():
		return default
	assert(ret[0].size() > col_index, "Invalid col_index: %s" % col_index)
	var arr = []
	for i in ret:
		arr.push_back(i[col_index])
	return arr
	
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
