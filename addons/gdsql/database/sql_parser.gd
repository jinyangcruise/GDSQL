extends RefCounted
class_name SQLParser

static var re_select: RegEx = RegEx.new()
static var re_update: RegEx = RegEx.new()
static var re_delete: RegEx = RegEx.new()
static var re_insert: RegEx = RegEx.new()
static var re_replace: RegEx = RegEx.new()

static func _static_init() -> void:
	# 不支持嵌套，比如select a from (select a from user)
	re_select.compile(r"(?is)(SELECT|FROM|WHERE|LEFT\s+JOIN|ON)\s+(.*?)(?=\s+FROM|\s+WHERE|\s+LEFT\s+JOIN|\s+ON|$)")
	re_update.compile(r"(?is)(UPDATE|SET|WHERE)\s+(.*?)(?=\s+SET|\s+WHERE|$)")
	re_delete.compile(r"(?is)(DELETE\s+FROM|WHERE)\s+(.*?)(?=\s+WHERE|$)")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO|VALUES|ON\s+DUPLICATE\s+KEY\s+UPDATE)\s+(.*?)(?=\s+VALUES|\s+ON\s+DUPLICATE\s+KEY\s+UPDATE|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO|VALUES)\s+(.*?)(?=\s+VALUES\s*|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))") correct
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE\s*(.*))?$")
	#re_insert.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	re_insert.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))")
	
static func parse_select(sql: String) -> Array:
	var matches = re_select.search_all(sql.strip_edges())
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), i.get_string(2).strip_edges()])
	return ret
	
static func parse_update(sql: String) -> Array:
	var matches = re_update.search_all(sql.strip_edges())
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), i.get_string(2).strip_edges()])
	return ret
	
static func parse_delete(sql: String) -> Array:
	var matches = re_delete.search_all(sql.strip_edges())
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), i.get_string(2).strip_edges()])
	return ret
	
static func parse_insert(sql: String) -> Array:
	var m = re_insert.search(sql.strip_edges())
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # insert into 
			m.get_string(2).strip_edges(), # table(x,y,z)
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			m.get_string(5).strip_edges(), # (1,2,3)
			m.get_string(6).strip_edges(), # on duplicate key update
			m.get_string(7).strip_edges(), # xxx
		]
		return ret
	return []
	
static func parse_replace(sql: String) -> Array:
	var m = re_replace.search(sql.strip_edges())
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # replace into 
			m.get_string(2).strip_edges(), # table(x,y,z)
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			m.get_string(5).strip_edges(), # (1,2,3)
			m.get_string(6).strip_edges(), # on duplicate key update
			m.get_string(7).strip_edges(), # xxx
		]
		return ret
	return []
