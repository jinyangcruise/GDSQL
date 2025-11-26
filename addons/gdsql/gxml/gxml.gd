## GXML can parse xml file or xml-formatted String or buffer to a Dictionary.
## Usage: 
##     var gxml = load("res://1.xml")
##     var dict = gxml.to_dict(GXML.TO_DICT_FLAG.COMBINE_TEXTS | GXML.TO_DICT_FLAG.IGNORE_PLAIN_BLANK_TEXT)
##     print(dict)
## Limit:
##     Do not support multiple roots. Use a tag to wrap your content.
##     eg:
##     original file:
##         <a>...</a>
##         <b>...</b>
##     modify to:
##         <abc>
##             <a>...</a>
##             <b>...</b>
##         </abc>
@tool
@icon("res://addons/gdsql/gbatis/img/xml.svg")
extends Resource
class_name GXML

var root_item: GDSQL.GXMLItem

## Some features that to_dict() uses. You can combine these flags.
enum TO_DICT_FLAG {
	## default. No Features.
	## 不使用特征。
	NONE = 0, 
	## Ignore plain blank text(' ', '\t', '\n', '\n\r') and their combinations in "content" array.
	## "content"将忽略纯空白字符及其组合。
	IGNORE_PLAIN_BLANK_TEXT = 1,
	## Combine continuous elements which are text in "content" array.
	## "content"将把连续的文本元素合并为一个单独的文本元素。
	COMBINE_ADJACENT_TEXTS = 2,
	## IGNORE_PLAIN_BLANK_TEXT和COMBINE_ADJACENT_TEXTS
	NORMAL = 3,
}

## return Dictionary: {
##	"name": String,
##	"attrs": Dictionary{ property_name: value},
##	"content": Array[String or Dictionary which contains "name", "attrs" and "content"]
## }
func to_dict(flags: TO_DICT_FLAG = TO_DICT_FLAG.NORMAL) -> Dictionary:
	assert(root_item, "use load() to load a xml file.")
	return root_item.to_dict(flags)
	
func _validate_property(property: Dictionary) -> void:
	if property.name == "root_item":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
