extends RefCounted
class_name QueryResult

var _err = OK
var _affected_rows = 0
var _warnings
var _data
var _last_insert_id = 0

func ok() -> bool:
	return _err is int and _err == OK
	
func get_err():
	return _err
	
func get_affected_rows() -> int:
	return _affected_rows
	
func get_warnings() -> Array:
	return [] if _warnings == null else _warnings
	
## 获取query后的原始返回数据，包括表头和数据
func get_raw_data() -> Array:
	return [] if _data == null else _data
	
## 获取query后的数据，不包括表头
func get_data() -> Array:
	if _data is Array and _data.size() > 1:
		return (_data as Array).slice(1)
	return []
	
## 获取query后的数据的表头
func get_head() -> Array:
	if _data is Array and _data.size() > 0:
		return (_data as Array)[0]
	return []
	
func get_last_insert_id():
	return _last_insert_id
