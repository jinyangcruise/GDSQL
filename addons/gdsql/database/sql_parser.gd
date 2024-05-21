extends RefCounted
class_name SQLParser

static var re_select: RegEx = RegEx.new()
static var re_update: RegEx = RegEx.new()
static var re_insert: RegEx = RegEx.new()
static var re_delete: RegEx = RegEx.new()

static func _static_init() -> void:
	# 不支持嵌套，比如select a from (select a from user)
	re_select.compile(r"(?is)(SELECT|FROM|WHERE|LEFT JOIN|ON)\s+(.*?)(?=\s+FROM|\s+WHERE|\s+LEFT JOIN|\s+ON|$)")
	re_update.compile(r"(?is)(UPDATE|SET|WHERE)\s+(.*?)(?=\s+SET|\s+WHERE|$)")
	re_insert.compile(r"(?is)(INSERT INTO|VALUES)\s+(.*?)(?=\s+VALUES|$)")
	re_delete.compile(r"(?is)(DELETE FROM|WHERE)\s+(.*?)(?=\s+WHERE|$)")
	
static func parse(sql: String) -> Array:
	var matches = re_select.search_all(sql)
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), i.get_string(2).strip_edges()])
	return ret
