@tool
extends Resource

## 节点类型
var type: XMLParser.NodeType
## 节点名称
var name: String
## 节点开始位置
var start: int
## 节点结束位置
var end: int
## 所处的原文件的行号
var line: int
## 属性列表
var attrs: Dictionary
## 内容
var data: String
## 原始
var raw: String
## 是否为空，例如<element />
var is_empty: bool

static var _cdata_regex: RegEx

static func _static_init():
	_cdata_regex = RegEx.new()
	_cdata_regex.compile("(?ms)<!\\[CDATA\\[(.*?)\\]\\]>") # extract content
	
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"type", "name", "start", "end", "attrs", "data", "raw", "is_empty":
			property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
			
func is_element_like() -> bool:
	return is_element() or is_element_end()

func is_element() -> bool:
	return type == XMLParser.NODE_ELEMENT
	
func is_element_end() -> bool:
	return type == XMLParser.NODE_ELEMENT_END
	
func is_text() -> bool:
	return type == XMLParser.NODE_TEXT
	
func is_blank_text() -> bool:
	assert(is_text(), "node_type != NODE_TEXT")
	return data.strip_edges().is_empty()
	
func is_cdata() -> bool:
	return type == XMLParser.NODE_CDATA
	
func get_cdata() -> String:
	assert(is_cdata(), "node_type != NODE_CDATA")
	var mat = _cdata_regex.search(raw)
	if mat:
		return mat.get_string(1)
	return ""
