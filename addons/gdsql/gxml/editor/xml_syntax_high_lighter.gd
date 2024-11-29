@tool
extends SyntaxHighlighter
class_name XMLSyntaxHighLighter

@export var element_color: Color = EDITOR_GET("text_editor/theme/highlighting/gdscript/node_path_color")
@export var attr_key_color: Color = EDITOR_GET("text_editor/theme/highlighting/member_variable_color")
@export var text_color: Color = EDITOR_GET("text_editor/theme/highlighting/text_color")
@export var symbol_color: Color = EDITOR_GET("text_editor/theme/highlighting/symbol_color")
@export var keyword_color: Color = EDITOR_GET("text_editor/theme/highlighting/keyword_color")
@export var number_color: Color = EDITOR_GET("text_editor/theme/highlighting/number_color")
@export var boolean_color: Color = EDITOR_GET("editors/visual_editors/connection_colors/boolean_color")
@export var string_color: Color = EDITOR_GET("text_editor/theme/highlighting/string_color")
@export var member_variable_color: Color = EDITOR_GET("text_editor/theme/highlighting/member_variable_color")
@export var function_color: Color = EDITOR_GET("text_editor/theme/highlighting/function_color")
@export var engine_type_color: Color = EDITOR_GET("text_editor/theme/highlighting/engine_type_color")

@export var symbols: Array[String] = ["~", "!", "%", "^", "&", "*", "(", ")", "[", "]", "{", "}", "+", "-", "/", "="]
@export var keywords: Array[String] = ["var", "null", "and", "or", "not"]
@export var functions: Array[String]
@export var engine_types: Array[String]

var error: bool = false

## {line => [arr_node]}
var line_cache: Dictionary

## 每行累计字符个数
var line_begin_pos = [0]


func _update_cache() -> void:
	element_color = EDITOR_GET("text_editor/theme/highlighting/gdscript/node_path_color")
	attr_key_color = EDITOR_GET("text_editor/theme/highlighting/member_variable_color")
	text_color = EDITOR_GET("text_editor/theme/highlighting/text_color")
	symbol_color = EDITOR_GET("text_editor/theme/highlighting/symbol_color")
	keyword_color = EDITOR_GET("text_editor/theme/highlighting/keyword_color")
	number_color = EDITOR_GET("text_editor/theme/highlighting/number_color")
	boolean_color = EDITOR_GET("editors/visual_editors/connection_colors/boolean_color")
	string_color = EDITOR_GET("text_editor/theme/highlighting/string_color")
	member_variable_color = EDITOR_GET("text_editor/theme/highlighting/member_variable_color")
	function_color = EDITOR_GET("text_editor/theme/highlighting/function_color")
	engine_type_color = EDITOR_GET("text_editor/theme/highlighting/engine_type_color")
	
func _clear_highlighting_cache():
	line_cache.clear()
	line_begin_pos = [0]
	
func _get_line_syntax_highlighting(p_line: int) -> Dictionary:
	var color_map = {}
	if error:
		return color_map
		
	if line_cache.is_empty():
		# 每行的起始字符位置
		line_begin_pos = [0]
		var text_edit = get_text_edit()
		var content = text_edit.text
		if not text_edit.text_changed.is_connected(_clear_highlighting_cache):
			text_edit.text_changed.connect(_clear_highlighting_cache)
			text_edit.text_set.connect(_clear_highlighting_cache)
		var p = -1
		for i in content:
			p += 1
			if i == "\n":
				line_begin_pos.push_back(p + 1)
		# 解析xml
		parse(content)
		
	for node: GXMLNode in line_cache.get(p_line, []):
		match node.type:
			XMLParser.NodeType.NODE_NONE:
				pass
			XMLParser.NodeType.NODE_ELEMENT, XMLParser.NodeType.NODE_ELEMENT_END:
				var line_str = get_text_edit().get_line(p_line)
				var start = 0
				var end = 0
				#var offset0 = line_begin_pos[p_line] - node.start
				#start = node.raw.find(node.name) - offset0
				var same_line_nodes = line_cache[p_line]
				var pre_node: GXMLNode
				for n in same_line_nodes:
					if n == node:
						break
					pre_node = n
				var offset = 0 if pre_node == null else pre_node.end - line_begin_pos[p_line]
				start = line_str.find(node.name, offset)
				if start == -1:
					printt("break", node.name, offset)
					break
				end = start + node.name.length()
				_gen_color_info(color_map, node.name, start, end, element_color)
				#printt("p_line:", p_line, 'line_str:|%s|' % line_str, "start:", start, "end:", end, "node.start:", 
					#node.start, "node.end:", node.end, "line_begin_pos[p_line]:", line_begin_pos[p_line])
					
				# 属性
				for attr_key: String in node.attrs:
					# key
					start = line_str.find(attr_key, end)
					if start == -1:
						break
						
					end = start + attr_key.length()
					_gen_color_info(color_map, attr_key, start, end, attr_key_color)
					
					# value
					var attr_value = node.attrs[attr_key]
					start = line_str.find(attr_value, end)
					end = start + attr_value.length()
					_gen_color_info(color_map, attr_value, start, end)
					
	#printt("gggggg", color_map)
	return color_map
	
func _gen_color_info(color_map: Dictionary, word: String, start: int, end: int, color = null):
	if color == null:
		if word.is_valid_float():
			color = number_color
		elif word in ["true", "false"]:
			color = boolean_color
		elif word in keywords:
			color = keyword_color
		elif word in functions:
			color = function_color
		elif word in engine_types:
			color = engine_type_color
		else:
			color = string_color
			
	color_map[start] = {"color": color}
	color_map[end] = {"color": text_color}
	
func parse(xml_string: String):
	line_cache.clear()
	if xml_string.is_empty():
		return
	var content = xml_string.to_utf8_buffer()
	var parser = XMLParser.new()
	parser.open_buffer(content)
	var arr_data = []
	while parser.read() != ERR_FILE_EOF:
		var node = GXMLNode.new()
		node.type = parser.get_node_type()
		node.name = parser.get_node_name() if node.is_element_like() else ""
		node.start = parser.get_node_offset()
		node.line = parser.get_current_line()
		node.is_empty = parser.is_empty()
		
		if node.is_element():
			for i in parser.get_attribute_count():
				node.attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
		if node.is_text():
			node.data = parser.get_node_data()
		arr_data.push_back(node)
		
		var line_of_start = binary_search(node.start)
		for i in range(line_of_start, node.line + 1):
			if not line_cache.has(i):
				line_cache[i] = []
			line_cache[i].push_back(node)
			
	for i in arr_data.size():
		arr_data[i].end = arr_data[i+1].start if (i+1 < arr_data.size()) else content.size()
		arr_data[i].raw = content.slice(arr_data[i].start, arr_data[i].end).get_string_from_utf8()
		
func binary_search(target):
	var left = 0
	var right = len(line_begin_pos) - 1
	
	while left <= right:
		@warning_ignore("integer_division")
		var mid = (left + right) / 2# 计算中间位置
		if line_begin_pos[mid] == target:
			return mid# 找到了目标值
		elif line_begin_pos[mid] < target:
			left = mid + 1# 目标在右侧
		else:
			right = mid - 1# 目标在左侧
	# 如果没有找到目标值，`left` 就是正确的插入位置
	return left - 1
#func cache_item(item: GXMLItem):
	#for i in range(item.line)
	
#var highlighter: CodeHighlighter = Codenew()

#func _get_name() -> String:
	#return tr("xml")
	#
#func _get_supported_languages() -> PackedStringArray:
	#return ["xml"]
	
#func _get_line_syntax_highlighting(p_line):
	#var ret = get_line_syntax_highlighting(p_line)
	#printt("gwwwww", p_line, ret)
	#
#func _init() -> void:
	#clear_keyword_colors()
	#clear_member_keyword_colors()
	#clear_color_regions()
	#
	## Disable automatic symbolic highlights, as these don't make sense for prose.
	#set_symbol_color(EDITOR_GET("text_editor/theme/highlighting/symbol_color"))
	#set_number_color(EDITOR_GET("text_editor/theme/highlighting/number_color"))
	#set_member_variable_color(EDITOR_GET("text_editor/theme/highlighting/member_variable_color"))
	#set_function_color(EDITOR_GET("text_editor/theme/highlighting/function_color"))
	#
	#var code_color = EDITOR_GET("text_editor/theme/highlighting/engine_type_color")
	#
	## Link (both references and inline links with URLs). The URL is not highlighted.
	#var link_color = EDITOR_GET("text_editor/theme/highlighting/keyword_color")
	#
	## XML标签
	#_add_color_region("<", ">", symbol_color, true)  # 标签可以是多行的
	#_add_color_region("</", ">", symbol_color, true) # 结束标签
#
	## 属性名称
	##add_color_region(" ", "=", member_variable_color, true) # 在空格和等号之间的内容作为属性名
	#_add_color_region("=", " ", member_variable_color, true) # 等号后的第一个空格前的内容作为属性值
#
	## 属性值（通常在引号内）
	#var quote_color = EDITOR_GET("text_editor/theme/highlighting/string_color")
	#_add_color_region("\"", "\"", quote_color, false) # 双引号内的值
	#_add_color_region("'", "'", quote_color, false)   # 单引号内的值
#
	## 注释
	#var comment_color = EDITOR_GET("text_editor/theme/highlighting/comment_color")
	#_add_color_region("<!--", "-->", comment_color, true) # 多行注释
#
	## CDATA部分
	##_add_color_region("<![CDATA[", "]]>", quote_color, true) # CDATA区域
	#
#func _add_color_region(p_start_key, p_end_key, p_color, p_line_only):
	#for i in p_start_key:
		#if not is_symbol(i):
			#printt("gggggggg not symbol", i)
	#add_color_region(p_start_key, p_end_key, p_color, p_line_only)
	#
	
#func is_digit(c: String) -> bool:
	#return c >= '0' and c <= '9'
	#
#func is_symbol(c: String) -> bool:
	#return c != '_' and ((c >= '!' and c <= '/') or (c >= ':' and c <= '@') or \
	#(c >= '[' and c <= '`') or (c >= '{' and c <= '~') or c == '\t' or c == ' ')
	#
#func is_hex_digit(c: String):
	#return (is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))
	#
#func is_ascii_alphabet_char(p_char: String) -> bool:
	#return (p_char >= 'a' && p_char <= 'z') || (p_char >= 'A' && p_char <= 'Z')
	#
#func is_underscore(p_char: String) -> bool:
	#return (p_char == '_')
	
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
#class ColorRegion:
	#var color: Color
	#var start_key: String
	#var end_key: String
	#var line_only := false
