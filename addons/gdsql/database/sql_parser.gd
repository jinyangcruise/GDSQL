@tool
extends RefCounted
class_name SQLParser

static var re_split_comma: RegEx = RegEx.new()
static var re_split_equal: RegEx = RegEx.new()
static var re_field_value: RegEx = RegEx.new()
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
	re_split_comma.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	re_split_equal.compile("=(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	re_field_value.compile(r'(?i)^\b([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*values\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)\s*$')
	# 不支持嵌套，比如select a from (select a from user)
	#re_select.compile(r"(?is)(SELECT|FROM|WHERE|LEFT\s+JOIN|ON|UNION|ORDER\s+BY|LIMIT)\s+(.*?)(?=\s+SELECT|\s+FROM|\s+WHERE|\s+LEFT\s+JOIN|\s+ON|\s+UNION|\s+ORDER\s+BY|\s+LIMIT|$)")
	# 与上面的区别是，下面这个支持UNION后跟SELECT，上面的必须在UNION和SELECT中间插入额外的字符比如ALL。
	# 用下面的可以支持UNION和UNION ALL。用上面的只能是UNION ALL或自定义一个UNION CUSTOM。
	re_select.compile(r"(?is)(\bSELECT|FROM|WHERE|LEFT\s+JOIN|ON|UNION|ORDER\s+BY|LIMIT)\s+(.*?)(?=\bSELECT|\s+FROM|\s+WHERE|\s+LEFT\s+JOIN|\s+ON|\s+UNION|\s+ORDER\s+BY|\s+LIMIT|$)")
	re_update.compile(r"(?is)(UPDATE|SET|WHERE)\s+(.*?)(?=\s+SET|\s+WHERE|$)")
	re_delete.compile(r"(?is)(DELETE\s+FROM|WHERE)\s+(.*?)(?=\s+WHERE|$)")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO|VALUES|ON\s+DUPLICATE\s+KEY\s+UPDATE)\s+(.*?)(?=\s+VALUES|\s+ON\s+DUPLICATE\s+KEY\s+UPDATE|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO|VALUES)\s+(.*?)(?=\s+VALUES\s*|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))") correct
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE\s*(.*))?$")
	#re_insert.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	re_insert.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	# 这个正则表达式是用来匹配SQL语句中的`INSERT`语句的，包括一些变体如`INSERT INTO`, `INSERT IGNORE INTO`, 以及可能包含的`VALUES`子句、`ON DUPLICATE KEY UPDATE`子句等部分。下面是对这个正则表达式的逐步解析：
	#- `(?is)`: 正则表达式的标志位，其中`i`表示忽略大小写（case-insensitive），`s`表示点`.`可以匹配包括换行符在内的任意字符（dotall模式）。
	#- `(INSERT(?:\s+IGNORE)?\s+INTO)`: 匹配以`INSERT`开始，后面可能跟零个或1个`IGNORE`关键字（每个`IGNORE`前后可能有任意数量的空白字符），之后是至少一个空白字符和`INTO`关键字。这部分整体用来匹配`INSERT INTO`或`INSERT IGNORE INTO`这样的开头。
		#解释：
		#(?:...): 非捕获组，用于组合模式但不捕获匹配的内容。
		#\s+IGNORE: 匹配IGNORE关键字前的一个或多个空白字符。
		#?: 表示前面的模式（在这里是非捕获组(?:\s+IGNORE)）可以出现0次或1次。
		#所以，整个修改后的正则表达式片段确保了IGNORE如果出现，就只出现一次，并且它前后可以有任意数量的空白字符，但不会连续出现多次IGNORE。
	#- `\s+`: 匹配一个或多个空白字符。
	#- `((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)`: 这是一个捕获组，匹配表名。
		#这个表达式分为两大部分，分别用于捕获表名（包括可能的数据库名）和可选的列名列表。
		#表名部分
			#(?:\s*\b[^\s.]+\b\s*\.\s*)*:
				#(?: ... ): 非捕获组，用于组合但不捕获匹配项。
				#\s*: 匹配任意数量的空白字符。
				#\b: 单词边界，确保我们匹配的是完整的单词，而非单词内部的点号。
				#[^\s.]+: 匹配一个或多个非空白字符和非点号的字符，即数据库名或表名的组成部分。
				#\s*\.\s*: 匹配点号及其前后可能存在的任意数量的空白字符。
				#*：前面整个模式可以重复任意次，意味着可以匹配多个数据库名和表名组成的路径，每个部分之间用点号分隔，且点号周围可以有空白字符。
			#\s*\b[^\s.]+\b\s*:
				#这部分单独匹配最终的表名，同样利用\b来确保匹配完整的表名单词，且表名前后可以有空白字符。
				#列名列表部分
				#(?:\s*\([^)]*\))?:
				#(?:\s* 和 )?)：依然是非捕获组，用于整个列名列表部分，后面跟一个?表示这部分是可选的。
				#\([^)]*\)：匹配一对圆括号内的任何字符（除了右括号），即列名列表，比如(column1, column2)。
	#- `\s+`: 再次匹配一个或多个空白字符。
	#- `(VALUES)`: 匹配关键词`VALUES`。
	#- `\s*`: 匹配零个或多个空白字符。
	#- `(\([^)]*\))`: 匹配`VALUES`后的值列表，即一对圆括号内的任何内容，不包括圆括号本身。
	#- `(\s*ON DUPLICATE KEY UPDATE)?`: 这是一个可选的捕获组，匹配`ON DUPLICATE KEY UPDATE`子句，前后可以有任意数量的空白字符。
	#- `(\s*.*)?`: 最后一个可选的捕获组，匹配`ON DUPLICATE KEY UPDATE`子句后面可能跟随的任何内容，这部分主要用于捕获该子句后面的更新设置，如果有。
	#综上所述，这个正则表达式用于详细解析并捕获SQL `INSERT`语句的不同部分，包括是否包含`IGNORE`关键字、表名、列名、值列表、以及是否包含`ON DUPLICATE KEY UPDATE`子句及其具体内容，适用于分析和处理各种格式的插入语句。
	re_insert.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	#re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))")
	re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))")
	
static func parse_to_dao(sql: String) -> BaseDao:
	sql = sql.strip_edges()
	if sql.countn("select", 0, 6) > 0:
		var arr = parse_select(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your SELECT sql."))
		assert(_assert(arr.size() >= 2, "SELECT need at least SELECT and FROM."))
		assert(_assert(not arr[0][1].is_empty(), "Missing fields after SELECT."))
		assert(_assert(arr[1][0].to_upper() == "FROM", "Missing FROM after SELECT."))
		
		var db_table_alias = _get_db_table_alias(arr[1][1])
		if not db_table_alias:
			return null
		var db = db_table_alias[0]
		var table = db_table_alias[1]
		var alias = db_table_alias[2]
		
		var dao = BaseDao.new()
		var first_dao = dao
		if not db.is_empty():
			dao.use_db_name(db)
		dao.select(arr[0][1], true)
		dao.from(table, alias)
		var index = 2
		while arr.size() > index:
			var key_words = arr[index][0].to_upper() as String
			if key_words.contains("LEFT"):
				assert(_assert(arr.size() > index + 1, "Missing ON of LEFT JOIN."))
				assert(_assert(arr[index+1][0].to_upper() == "ON", "Missing ON of LEFT JOIN."))
				var left_join_db_table_alias = _get_db_table_alias(arr[index][1])
				if not left_join_db_table_alias:
					return null
				var left_join_db = left_join_db_table_alias[0]
				var left_join_table = left_join_db_table_alias[1]
				var left_join_alias = left_join_db_table_alias[2]
				var on = arr[index+1][1]
				dao.left_join(left_join_db, left_join_table, left_join_alias, on, "")
				index += 2
			elif key_words.contains("WHERE"):
				assert(_assert(not arr[index][1].is_empty(), "MISSING condition after WHERE."))
				dao.where(arr[index][1])
				index += 1
			elif key_words.contains("UNION"):
				# for now only support union all
				assert(_assert(arr[index][1].to_upper() == "ALL", "ONLY SUPPORT UNION ALL."))
				assert(_assert(arr.size() > index + 1, "Missing SELECT after UNION."))
				assert(_assert(arr[index+1][0].to_upper() == "SELECT", "Missing SELECT after UNION."))
				dao = dao.union_all()
				index += 1
			elif key_words.contains("SELECT"):
				assert(_assert(not arr[index][1].is_empty(), "Missing fields after SELECT."))
				assert(_assert(arr.size() > index + 1, "Missing FROM after SELECT."))
				assert(_assert(arr[index+1][0].to_upper() == "FROM", "Missing FROM after SELECT."))
				var a_db_table_alias = _get_db_table_alias(arr[index+1][1])
				if not a_db_table_alias:
					return null
				var a_db = a_db_table_alias[0]
				var a_table = a_db_table_alias[1]
				var a_alias = a_db_table_alias[2]
				if not a_db.is_empty():
					dao.use_db_name(a_db)
				dao.select(arr[index][1], false) # dao of union all
				dao.from(a_table, a_alias)
				index += 2
			elif key_words.contains("ORDER"):
				assert(_assert(not arr[index][1].is_empty(), "Missing Field after ORDER BY."))
				dao.order_by_str(arr[index][1])
				index += 1
			elif key_words.contains("LIMIT"):
				assert(_assert(not arr[index][1].is_empty(), "Missing number after LIMIT."))
				var splits = (arr[index][1] as String).split_floats(".")
				assert(_assert(splits.size() == 1 or splits.size() == 2, 
					"Incorrect number after LIMIT. %s" % arr[index][1]))
				if splits.size() == 1:
					dao.limit(0, splits[0])
				else:
					dao.limit(splits[0], splits[1])
				index += 1
		return first_dao
	elif sql.countn("update", 0, 6) > 0:
		var arr = parse_update(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your UPDATE sql."))
		assert(_assert(arr[1][0].to_upper() == "SET", "Missing SET after UPDATE."))
		assert(_assert(arr.size() <= 3, "Redundant info near: [%s]" % arr[3][0] if arr.size() > 3 else ""))
		var db_table = _get_db_table(arr[0][1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = BaseDao.new()
		if not db.is_empty():
			dao.use_db_name(db)
		dao.update(table)
		
		var sets = _get_set_value_list(arr[1][1])
		assert(_assert(not sets.is_empty(), "Error near: [%s]" % arr[1][1]))
		dao.sets(sets)
		
		if arr.size() > 2:
			assert(_assert(arr[2][0].to_upper() == "WHERE", "Invalid keyword near: [%s]" % arr[2][0]))
			dao.where(arr[2][1])
			
		return dao
	elif sql.countn("delete", 0, 6) > 0:
		var arr = parse_delete(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your DELETE sql."))
		assert(_assert(arr.size() <= 2, "Cannot parse your DELETE sql."))
		var db_table = _get_db_table(arr[0][1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = BaseDao.new()
		if not db.is_empty():
			dao.use_db_name(db)
		dao.delete_from(table)
		
		if arr.size() == 2:
			assert(_assert(arr[1][0].to_upper() == "WHERE", "Invalid keyword near: [%s]" % arr[2][0]))
			dao.where(arr[1][1])
			
		return dao
	elif sql.countn("insert", 0, 6) > 0:
		var arr = parse_insert(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your INSERT sql."))
		assert(_assert(arr[3].to_upper() == "VALUES", "Parser error of keyword VALUES."))
		if not arr[5].is_empty():
			assert(_assert(arr[5].countn("duplicate"), "Parser error of keyword ON DUPLICATE KEY UPDATE."))
		var db_table = _get_db_table(arr[1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = BaseDao.new()
		if not db.is_empty():
			dao.use_db_name(db)
		if (arr[0] as String).countn("ignore") > 0:
			assert(_assert(not arr[5].is_empty(), 
				"Cannot use INSERT IGNORE and ON DUPLICATE KEY UPDATE at the same time."))
			dao.insert_ignore(table)
		elif not (arr[5] as String).is_empty(): # on duplicate key update
			assert(_assert(not arr[6].is_empty(), "Missing set value after ON DUPLICATE KEY UPDATE."))
			dao.insert_or_update(table)
		else:
			dao.insert_into(table)
			
		# fields
		var fields = _get_field_list(arr[2]) if not arr[2].is_empty() else []
		# values
		var values = _get_value_list(arr[4], true)
		var data = {}
		if fields.size() > 0 and values.size() > 0:
			assert(_assert(fields.size() == values.size(), "Fields count and Values count not match."))
			for i in fields.size():
				data[fields[i]] = values[i]
		dao.values(values)
		if data.is_empty():
			dao.values(values)
		else:
			dao.values(data)
			
		# set value of on duplicate key update
		if not arr[6].is_empty():
			var set_values = _get_value_list(arr[6], false)
			var update_fields = []
			for i in set_values:
				var field_value = _get_field_value(i)
				assert(_assert(not field_value.is_empty(), "Not support this: [%s]." % i))
				assert(_assert(field_value[0] == field_value[1], "Not support this: [%s]." % i))
				update_fields.push_back(field_value[0])
			assert(_assert(not update_fields.is_empty(), "Invalid set value after ON DUPLICATE KEY UPDATE."))
			dao.on_duplicate_update(fields)
			
		return dao
	elif sql.countn("replace", 0, 7) > 0:
		var arr = parse_replace(sql)
		assert(_assert(not arr.is_empty(), "Cannot parse your REPLACE sql."))
		assert(_assert(arr[3].to_upper() == "VALUES", "Parser error of keyword VALUES."))
		var db_table = _get_db_table(arr[1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = BaseDao.new()
		if not db.is_empty():
			dao.use_db_name(db)
		dao.replace_into(table)
		
		# fields
		var fields = _get_field_list(arr[2]) if not arr[2].is_empty() else []
		
		# values
		var values = _get_value_list(arr[4], true)
		var data = {}
		if fields.size() > 0 and values.size() > 0:
			assert(_assert(fields.size() == values.size(), "Fields count and Values count not match."))
			for i in fields.size():
				data[fields[i]] = values[i]
		dao.values(values)
		if data.is_empty():
			dao.values(values)
		else:
			dao.values(data)
		return dao
	else:
		assert(_assert(false, "Sql should begin with one of [SELECT, UPDATE, DELETE, INSERT, REPLACE]."))
	return null
	
static func parse_select(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_select.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	return ret
	
static func parse_update(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_update.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	return ret
	
static func parse_delete(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_delete.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	return ret
	
static func parse_insert(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var rm = prepare[1]
	var m = re_insert.search(prepare[0])
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # insert into
			restore(m.get_string(2).strip_edges(), rm), # db.table
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			restore(m.get_string(5).strip_edges(), rm), # (1,2,3)
			m.get_string(6).strip_edges(), # on duplicate key update
			restore(m.get_string(7).strip_edges(), rm), # xxx
		]
		ret = _check_semicolon(ret)
		return ret
	return []
	
static func parse_replace(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var rm = prepare[1]
	var m = re_replace.search(prepare[0])
	if m:
		var ret = [
			m.get_string(1).strip_edges(), # replace into
			restore(m.get_string(2).strip_edges(), rm), # db.table
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			restore(m.get_string(5).strip_edges(), rm), # (1,2,3)
		]
		ret = _check_semicolon(ret)
		return ret
	return []

static func extract_outer_quotes(text):
	var stack = []  # 用于跟踪当前处理的引号层级
	var result = []  # 存储提取的引号内容
	var current_string = ""  # 临时存储正在构建的引号内字符串
	var quote_types = {"\"": "\"", "\'": "\'"}
	var in_quote = false  # 标记当前是否在引号内
	
	for a_char in text:
		if a_char in quote_types.values():
			if not in_quote:  # 如果不在引号内，遇到引号则开始记录
				stack.append(a_char)  # 记录引号类型
				in_quote = true
			else:  # 已在引号内，遇到相同类型的引号结束记录
				if stack[stack.size() - 1] == a_char:
					var q = stack.pop_back()  # 移除栈顶的引号类型
					result.append("%s%s%s" % [q, current_string, q])  # 保存内容
					current_string = ""  # 重置临时字符串
					in_quote = false
				else:
					# 遇到不同类型的引号，视为普通字符
					current_string += a_char
		else:  # 非引号字符
			if in_quote:
				current_string += a_char
				
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
	
static func _check_semicolon(ret: Array) -> Array:
	for i in ret.size()-1:
		if ret[i] is Array:
			for j in ret[i].size():
				assert(_assert(not ret[i][j].ends_with(";"), 
					"Invalid semicolon found near [%s]" % ret[i][j]))
		else:
			assert(_assert(not ret[i].ends_with(";"), 
				"Invalid semicolon found near [%s]" % ret[i]))
	if ret[ret.size()-1] is Array:
		for j in ret[ret.size()-1].size():
			ret[ret.size()-1][j] = _remove_last_semicolon(ret[ret.size()-1][j])
	else:
		ret[ret.size()-1] = _remove_last_semicolon(ret[ret.size()-1])
	return ret
	
static func _remove_last_semicolon(s: String) -> String:
	if s.ends_with(";"): # 不要分号结尾
		s = s.substr(0, s.length()-1)
	return s
	
static func _get_db_table(s: String) -> Array[String]:
	if not s.contains("."):
		return ["", s.strip_edges()]
		
	var splits = s.split(".")
	assert(_assert(splits.size() == 2, "Wrong table format. Near [%s]." % s))
	return [splits[0].strip_edges(), splits[1].strip_edges()]
	
static func _get_db_table_alias(s: String) -> Array[String]:
	var db = s.get_slice(".", 0).strip_edges() if s.contains(".") else ""
	var table = s.get_slice(".", 1).strip_edges()
	var alias = ""
	table = table.replace("\t", " ")
	if table.contains(" "):
		var splits = table.split(" ", false)
		assert(_assert(splits.size() == 2, "Wrong table and alias. Near [%s]." % table))
		table = splits[0]
		alias = splits[1]
	return [db, table, alias]
	
## 去掉最外层括号
static func _extract_bracket(s: String) -> String:
	if s.begins_with("(") and s.ends_with(")"):
		s = s.substr(1, s.length()-2)
	return s
	
static func _extract_quote(s: String) -> String:
	if s.begins_with("'") and s.begins_with("'"):
		s = s.substr(1, s.length()-2)
	elif s.begins_with('"') and s.begins_with('"'):
		s = s.substr(1, s.length()-2)
	return s
	
## 不考虑非常规field名称，比如带引号的
static func _get_field_list(s: String) -> Array[String]:
	s = _extract_bracket(s)
	var splits = s.split(",")
	var ret = [] as Array[String]
	for i in splits:
		ret.push_back(i.strip_edges())
	return ret
	
## 获取逗号分隔的值列表。逗号在括号和引号内的不会分隔。
static func _get_value_list(s: String, remove_outer_quote: bool) -> Array[String]:
	s = _extract_bracket(s)
	var matches = re_split_comma.search_all(s)
	var ret = [] as Array[String]
	if not matches.is_empty():
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var value = s.substr(start, i.get_start() - start).strip_edges()
			if remove_outer_quote:
				value = _extract_quote(value)
			ret.push_back(value)
			start = i.get_end()
			
		# 别忘了还有最后一个逗号到最后
		if start < s.length():
			var value = s.substr(start).strip_edges()
			if remove_outer_quote:
				value = _extract_quote(value)
			ret.push_back(value)
	else:
		if remove_outer_quote:
			s = _extract_quote(s)
		ret.push_back(s)
	return ret
	
## deal column1 = xxx
static func _get_set_value(s: String) -> Array[String]:
	var m = re_split_equal.search(s)
	assert(_assert(true if m else false, "Error near: [%s]" % s))
	var first = s.substr(0, m.get_start()).strip_edges()
	var second = s.substr(m.get_end()).strip_edges()
	return [first, _extract_quote(second)]
	
## deal column1 = call_('1', \"abc\"), column2 = value2
static func _get_set_value_list(s: String) -> Dictionary:
	var sets = _get_value_list(s, false)
	var ret = {}
	for i in sets:
		var splits = _get_set_value(i)
		if not splits:
			return {}
		assert(_assert(not ret.has(splits[0]), "Duplicate set field near: [%s]" % s))
		ret[splits[0]] = splits[1]
	return ret
	
## deal b=values(xxx)
static func _get_field_value(s: String) -> Array[String]:
	var m = re_field_value.search(s)
	if m:
		return [m.get_string(1), m.get_string(2)]
	return []
