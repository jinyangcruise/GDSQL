extends RefCounted
class_name SQLParser

#static var re_quoted: RegEx = RegEx.new()
static var re_select: RegEx = RegEx.new()
static var re_update: RegEx = RegEx.new()
static var re_delete: RegEx = RegEx.new()
static var re_insert: RegEx = RegEx.new()
static var re_replace: RegEx = RegEx.new()

static func _assert(success: bool, msg: String) -> bool:
	if not success:
		push_error("You have an error in your SQL syntax. %s" % msg)
		return false
	return true
	
static func _static_init() -> void:
	#re_quoted.compile(r"(\".*?\"|'.*?')")
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
	
static func parse_to_dao(sql: String) -> BaseDao:
	sql = sql.strip_edges()
	if sql.countn("select", 0, 6) > 0:
		var arr = parse_select(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your SELECT sql."))
		assert(_assert(arr.size() >= 2, "SELECT need at least SELECT and FROM."))
		assert(_assert(arr[1][0].to_upper() == "FROM", "Missing FROM or wrong position of FROM."))
		var db = (arr[1][1] as String).get_slice(".", 0).strip_edges()
		var table = (arr[1][1] as String).get_slice(".", 1).strip_edges()
		var alias = ""
		table = table.replace("\t", " ")
		if table.contains(" "):
			var splits = table.split(" ", false)
			assert(_assert(splits.size() == 2, "Near [%s]." % table))
			table = splits[0]
			alias = splits[1]
		var dao = BaseDao.new()
		dao.use_db_name(db)
		# TODO
	elif sql.countn("update", 0, 6) > 0:
		var arr = parse_update(sql)
	elif sql.countn("delete", 0, 6) > 0:
		var arr = parse_delete(sql)
	elif sql.countn("insert", 0, 6) > 0:
		var arr = parse_insert(sql)
	elif sql.countn("replace", 0, 7) > 0:
		var arr = parse_replace(sql)
	else:
		_assert(false, "Sql should begin with one of [SELECT, UPDATE, DELETE, INSERT, REPLACE].")
	return null
	
static func parse_select(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_select.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	return ret
	
static func parse_update(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_update.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	return ret
	
static func parse_delete(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_delete.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	return ret
	
static func parse_insert(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var rm = prepare[1]
	var m = re_insert.search(prepare[0])
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # insert into
			restore(m.get_string(2).strip_edges(), rm), # table(x,y,z)
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			restore(m.get_string(5).strip_edges(), rm), # (1,2,3)
			m.get_string(6).strip_edges(), # on duplicate key update
			restore(m.get_string(7).strip_edges(), rm), # xxx
		]
		return ret
	return []
	
static func parse_replace(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var rm = prepare[1]
	var m = re_replace.search(prepare[0])
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # replace into
			restore(m.get_string(2).strip_edges(), rm), # table(x,y,z)
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			restore(m.get_string(5).strip_edges(), rm), # (1,2,3)
		]
		return ret
	return []

static func extract_outer_quotes(text):
	var stack = []  # 用于跟踪当前处理的引号层级
	var result = []  # 存储提取的引号内容
	var current_string = ""  # 临时存储正在构建的引号内字符串
	var quote_types = {"\"": "\"", "\'": "\'"}
	var in_quote = false  # 标记当前是否在引号内
	
	for char in text:
		if char in quote_types.values():
			if not in_quote:  # 如果不在引号内，遇到引号则开始记录
				stack.append(char)  # 记录引号类型
				in_quote = true
			else:  # 已在引号内，遇到相同类型的引号结束记录
				if stack[stack.size() - 1] == char:
					var q = stack.pop_back()  # 移除栈顶的引号类型
					result.append("%s%s%s" % [q, current_string, q])  # 保存内容
					current_string = ""  # 重置临时字符串
					in_quote = false
				else:
					# 遇到不同类型的引号，视为普通字符
					current_string += char
		else:  # 非引号字符
			if in_quote:
				current_string += char
				
	# 如果栈不为空，说明有开始引号没有匹配的结束引号
	if stack.size() > 0:
		push_error("Error: Unmatched quote found in the text: %s" % text)
		
	result.sort_custom(func(a, b): return a.length() > b.length())
	return result
	
static func prepare_sql(sql: String) -> Array:
	sql = sql.strip_edges()
	var quoted_matches = extract_outer_quotes(sql)
	var replacements = {}
	var index = -1
	for i in quoted_matches:
		index += 1
		var r = "___Rep%d___" % index
		replacements[r] = i
		sql = sql.replace(i, r)
	return [sql, replacements]
	
static func restore(s: String, map: Dictionary) -> String:
	if not s.contains("___Rep"):
		return s
	for k in map:
		s = s.replace(k, map[k])
	return s
