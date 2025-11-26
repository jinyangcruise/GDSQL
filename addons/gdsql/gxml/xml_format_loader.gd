@tool
extends ResourceFormatLoader
class_name ResourceFormatLoaderXML

const EXTENSION = "xml"

func _get_recognized_extensions() -> PackedStringArray:
	return [EXTENSION]
	
func _get_resource_type(path: String) -> String:
	return "Resource" if path.get_extension() == EXTENSION else ""
	
func _get_resource_script_class(path: String) -> String:
	return "GXML" if path.get_extension() == EXTENSION else ""
	
func _handles_type(type: StringName) -> bool:
	return ClassDB.is_parent_class(type, "Resource")
	
@warning_ignore("unused_parameter")
func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
		
	var root_item = _parse_file(path)
	var gxml = GXML.new()
	gxml.root_item = root_item
	return gxml
	
#func _init(xml):
	#if xml is PackedByteArray:
		#_parse_buffer(xml)
	#elif xml is String:
		#if (xml as String).is_absolute_path() or (xml as String).is_relative_path():
			#_parse_file(xml)
		#else:
			#_parse_string(xml)
	#else:
		#push_error("Param should be one of PackedByteArray or file path or xml-formated String.")
		
func _parse_file(file_path: String):
	# 这里没有使用FileAccess的get_file_as_string()是因为会在xml包含中文等字符的时候出现偏移量错误的问题，
	# 所以换成了get_file_as_bytes()可避免get_node_offset()与实际位置不匹配的问题。
	var content = FileAccess.get_file_as_bytes(file_path)
	var parser = XMLParser.new()
	var err = parser.open(file_path)
	if err != OK:
		printerr("XMLParser err: " + error_string(err))
		return null
	return _parse(parser, content)
	
func _parse_string(xml_string: String):
	var content = xml_string.to_utf8_buffer()
	var parser = XMLParser.new()
	parser.open_buffer(content)
	return _parse(parser, content)
	
func _parse_buffer(buffer: PackedByteArray):
	var parser = XMLParser.new()
	parser.open_buffer(buffer)
	return _parse(parser, buffer)
	
func _parse(parser: XMLParser, content: PackedByteArray) -> GDSQL.GXMLItem:
	var root_item: GDSQL.GXMLItem = null
	var arr_data = []
	while parser.read() != ERR_FILE_EOF:
		var node = GDSQL.GXMLNode.new()
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
		
	for i in arr_data.size():
		arr_data[i].end = arr_data[i+1].start if (i+1 < arr_data.size()) else content.size()
		if arr_data[i].is_cdata():
			arr_data[i].raw = content.slice(arr_data[i].start, arr_data[i].end).get_string_from_utf8()
			
	var curr_item: GDSQL.GXMLItem = null
	for i in arr_data.size():
		if i == arr_data.size() - 1 and not curr_item:
			break
		var node = arr_data[i]
		var type = node.type
		match type:
			XMLParser.NODE_NONE:
				pass
			XMLParser.NODE_ELEMENT:
				if not root_item:
					root_item = GDSQL.GXMLItem.new()
					root_item.name = node.name
					root_item.attrs = node.attrs
					root_item.line = node.line
					curr_item = root_item
				else:
					var element = GDSQL.GXMLItem.new()
					element.name = node.name
					element.attrs = node.attrs
					element.line = node.line
					element.parent = curr_item
					curr_item.content.push_back(element) # GXMLItem
					if not node.is_empty:# TODO FIXME
						curr_item = element
			XMLParser.NODE_ELEMENT_END:
				curr_item.end_line = node.line
				curr_item = curr_item.parent
				pass
			XMLParser.NODE_TEXT:
				if not node.data.strip_edges().is_empty():
					curr_item.content.push_back(node.data) # String
			XMLParser.NODE_COMMENT:
				pass
			XMLParser.NODE_CDATA:
				if not node.get_cdata().strip_edges().is_empty():
					curr_item.content.push_back(node.get_cdata()) # String
					# mark that this content is a CDATA
					curr_item.cdata_indexes.push_back(curr_item.content.size()-1)
			XMLParser.NODE_UNKNOWN:
				pass
				
	arr_data.clear()
	return root_item
