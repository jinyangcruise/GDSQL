@tool
extends Resource
class_name GXMLItem

## 节点名称
var name: String
## 属性列表
var attrs: Dictionary
## 子Item，可能包含GXMLItem、String
var content: Array
## 父
var parent: GXMLItem

func _validate_property(property: Dictionary) -> void:
	match property.name:
		"name", "attrs", "content":
			property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
			
func to_dict(flags: GXML.TO_DICT_FLAG) -> Dictionary:
	var a_content = []
	var pre_str = ""
	for i in content:
		if i is String:
			if (flags & GXML.TO_DICT_FLAG.IGNORE_PLAIN_BLANK_TEXT) and i.strip_edges().is_empty():
				continue
			if flags & GXML.TO_DICT_FLAG.COMBINE_ADJACENT_TEXTS:
				pre_str += i
			else:
				a_content.push_back(i)
		else:
			if not pre_str.is_empty():
				a_content.push_back(pre_str)
				pre_str = ""
			a_content.push_back((i as GXMLItem).to_dict(flags))
			
	if not pre_str.is_empty():
		a_content.push_back(pre_str)
		
	return {
		"name": name,
		"attrs": attrs,
		"content": a_content,
	}
	
func clean():
	parent = null
	attrs.clear()
	for i in content:
		if i is GXMLItem:
			i.clean()
	content.clear()
	
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		parent = null
		attrs.clear()
		for i in content:
			if i is GXMLItem:
				i.clean()
		content.clear()
