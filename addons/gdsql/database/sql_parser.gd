@tool
extends RefCounted

static var re_split_comma: RegEx = RegEx.new()
static var re_split_equal: RegEx = RegEx.new()
static var re_field_value: RegEx = RegEx.new()
static var re_select: RegEx = RegEx.new()
static var re_update: RegEx = RegEx.new()
static var re_delete: RegEx = RegEx.new()
static var re_insert: RegEx = RegEx.new()
static var re_replace: RegEx = RegEx.new()
static var lru_cache: SQLParserLRULink

static func _assert_false(msg: String):
	assert(false, "You have an error in your SQL syntax. %s" % msg)
	return null
	
static func _static_init() -> void:
	lru_cache = SQLParserLRULink.new()
	lru_cache.capacity = 1024
	re_split_comma.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	re_split_equal.compile("=(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	re_field_value.compile(r'(?i)^\b([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*values\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)\s*$')
	# 不支持嵌套，比如select a from (select a from user)
	#re_select.compile(r"(?is)(SELECT|FROM|WHERE|LEFT\s+JOIN|ON|UNION|ORDER\s+BY|LIMIT)\s+(.*?)(?=\s+SELECT|\s+FROM|\s+WHERE|\s+LEFT\s+JOIN|\s+ON|\s+UNION|\s+ORDER\s+BY|\s+LIMIT|$)")
	# 与上面的区别是，下面这个支持UNION后跟SELECT，上面的必须在UNION和SELECT中间插入额外的字符比如ALL。
	# 用下面的可以支持UNION和UNION ALL。用上面的只能是UNION ALL或自定义一个UNION CUSTOM。
	re_select.compile(r"(?is)(\bSELECT|FROM|WHERE|LEFT\s+JOIN|ON|GROUP\s+BY|UNION|ORDER\s+BY|LIMIT)\s+(.*?)(?=\bSELECT|\s+FROM|\s+WHERE|\s+LEFT\s+JOIN|\s+ON|\s+GROUP\s+BY|\s+UNION|\s+ORDER\s+BY|\s+LIMIT|$)")
	re_update.compile(r"(?is)(UPDATE|SET|WHERE)\s+(.*?)(?=\s+SET|\s+WHERE|$)")
	re_delete.compile(r"(?is)(DELETE\s+FROM|WHERE)\s+(.*?)(?=\s+WHERE|$)")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO|VALUES|ON\s+DUPLICATE\s+KEY\s+UPDATE)\s+(.*?)(?=\s+VALUES|\s+ON\s+DUPLICATE\s+KEY\s+UPDATE|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO|VALUES)\s+(.*?)(?=\s+VALUES\s*|$)")
	#re_insert_into.compile(r"(?is)(INSERT\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))") correct
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))")
	#re_insert_into.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE\s*(.*))?$")
	#re_insert.compile(r"(?is)(INSERT[\s+IGNORE]*\s+INTO)\s+([^\s(]+)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	#re_insert.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
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
	#re_insert.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s*(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	re_insert.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s*(VALUES)\s*(\((?:[^()]|\([^()]*\))*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	#re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s+(VALUES)\s*(\([^)]*\))")
	#re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s*(VALUES)\s*(\([^)]*\))")
	re_replace.compile(r"(?is)(REPLACE\s+INTO)\s+((?:\s*\b[^\s.]+\b\s*\.\s*)*\s*\b[^\s.]+\b\s*)((?:\s*\([^)]*\))?)\s*(VALUES)\s*(\((?:[^()]|\([^()]*\))*\))")
	
static func parse_to_dao(sql: String) -> GDSQL.BaseDao:
	sql = sql.strip_edges()
	if sql.countn("select", 0, 6) > 0:
		var arr = parse_select(sql)
		var db_table_alias = _get_db_table_alias(arr[1][1])
		if not db_table_alias:
			return null
		var db = db_table_alias[0]
		var table = db_table_alias[1]
		var alias = db_table_alias[2]
		
		var dao = GDSQL.BaseDao.new()
		var first_dao = dao
		if db != "":
			dao.use_db_name(db)
		dao.select(arr[0][1], true)
		dao.from(table, alias)
		var index = 2
		while arr.size() > index:
			var key_words = arr[index][0].to_upper() as String
			if key_words.contains("LEFT"):
				if arr.size() <= index + 1:
					return _assert_false("Missing ON of LEFT JOIN.")
				if arr[index+1][0].to_upper() != "ON":
					return _assert_false("Missing ON of LEFT JOIN.")
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
				if arr[index][1] == "":
					return _assert_false("Missing condition after WHERE.")
				dao.where(arr[index][1])
				index += 1
			elif key_words.contains("GROUP"):
				if arr[index][1] == "":
					return _assert_false("Missing Field after GROUP BY.")
				dao.group_by(arr[index][1])
				index += 1
			elif key_words.contains("UNION"):
				# for now only support union all
				if arr[index][1].to_upper() != "ALL":
					return _assert_false("ONLY SUPPORT UNION ALL.")
				if arr.size() <= index + 1:
					return _assert_false("Missing SELECT after UNION.")
				if arr[index+1][0].to_upper() != "SELECT":
					return _assert_false("Missing SELECT after UNION.")
				dao = dao.union_all()
				index += 1
			elif key_words.contains("SELECT"):
				if arr[index][1] == "":
					return _assert_false("Missing fields after SELECT.")
				if arr.size() <= index + 1:
					return _assert_false("Missing FROM after SELECT.")
				if arr[index+1][0].to_upper() != "FROM":
					return _assert_false("Missing FROM after SELECT.")
				var a_db_table_alias = _get_db_table_alias(arr[index+1][1])
				if not a_db_table_alias:
					return null
				var a_db = a_db_table_alias[0]
				var a_table = a_db_table_alias[1]
				var a_alias = a_db_table_alias[2]
				if a_db != "":
					dao.use_db_name(a_db)
				dao.select(arr[index][1], false) # dao of union all
				dao.from(a_table, a_alias)
				index += 2
			elif key_words.contains("ORDER"):
				if arr[index][1] == "":
					return _assert_false("Missing Field after ORDER BY.")
				dao.order_by_str(arr[index][1])
				index += 1
			elif key_words.contains("LIMIT"):
				if arr[index][1] == "":
					return _assert_false("Missing number after LIMIT.")
				var splits = (arr[index][1] as String).split_floats(",")
				if not (splits.size() == 1 or splits.size() == 2):
					return _assert_false(
					"Incorrect number after LIMIT. %s" % arr[index][1])
				if splits.size() == 1:
					dao.limit(0, splits[0])
				else:
					dao.limit(splits[0], splits[1])
				index += 1
		return first_dao
	elif sql.countn("update", 0, 6) > 0:
		var arr = parse_update(sql)
		var db_table = _get_db_table(arr[0][1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = GDSQL.BaseDao.new()
		if db != "":
			dao.use_db_name(db)
		dao.update(table)
		
		var sets = _get_set_value_list(arr[1][1])
		if sets.is_empty():
			return _assert_false("Error near: [%s]" % arr[1][1])
		dao.sets(sets)
		dao.set_evalueate_mode(true)
		
		if arr.size() > 2:
			if arr[2][0].to_upper() != "WHERE":
				return _assert_false("Invalid keyword near: [%s]" % arr[2][0])
			dao.where(arr[2][1])
			
		return dao
	elif sql.countn("delete", 0, 6) > 0:
		var arr = parse_delete(sql)
		var db_table = _get_db_table(arr[0][1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = GDSQL.BaseDao.new()
		if db != "":
			dao.use_db_name(db)
		dao.delete_from(table)
		
		if arr.size() == 2:
			if arr[1][0].to_upper() != "WHERE":
				return _assert_false("Invalid keyword near: [%s]" % arr[2][0])
			dao.where(arr[1][1])
			
		return dao
	elif sql.countn("insert", 0, 6) > 0:
		var arr = parse_insert(sql)
		var db_table = _get_db_table(arr[1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = GDSQL.BaseDao.new()
		if db != "":
			dao.use_db_name(db)
		if (arr[0] as String).countn("ignore") > 0:
			if arr[5] == "":
				return _assert_false(
				"Cannot use INSERT IGNORE and ON DUPLICATE KEY UPDATE at the same time.")
			dao.insert_ignore(table)
		elif arr[5] != "": # on duplicate key update
			if arr[6] == "":
				return _assert_false("Missing set value after ON DUPLICATE KEY UPDATE.")
			dao.insert_or_update(table)
		else:
			dao.insert_into(table)
			
		# fields
		var fields = _get_field_list(arr[2]) if arr[2] != "" else []
		# values
		var values = _get_value_list(arr[4], true)
		var data = {}
		if fields.size() > 0 and values.size() > 0:
			if fields.size() != values.size():
				return _assert_false("Fields count and Values count not match.")
			for i in fields.size():
				data[fields[i]] = values[i]
		if data.is_empty():
			dao.values(values)
		else:
			dao.values(data)
			
		# set value of on duplicate key update
		if arr[6] != "":
			var set_values = _get_value_list(arr[6], false)
			var update_fields = []
			for i in set_values:
				var field_value = _get_field_value(i)
				# NOTICE 限于on_duplicate_update方法，目前只支持a=values(a)这样的写法
				if field_value.is_empty():
					return _assert_false("Not support this: [%s]." % i)
				if field_value[0] != field_value[1]:
					return _assert_false("Not support this: [%s]." % i)
				update_fields.push_back(field_value[0])
			if update_fields.is_empty():
				return _assert_false("Invalid set value after ON DUPLICATE KEY UPDATE.")
			dao.on_duplicate_update(fields)
			
		return dao
	elif sql.countn("replace", 0, 7) > 0:
		var arr = parse_replace(sql)
		var db_table = _get_db_table(arr[1])
		if not db_table:
			return null
		var db = db_table[0]
		var table = db_table[1]
		
		var dao = GDSQL.BaseDao.new()
		if db != "":
			dao.use_db_name(db)
		dao.replace_into(table)
		
		# fields
		var fields = _get_field_list(arr[2]) if arr[2] != "" else []
		
		# values
		var values = _get_value_list(arr[4], true)
		var data = {}
		if fields.size() > 0 and values.size() > 0:
			if fields.size() != values.size():
				return _assert_false("Fields count and Values count not match.")
			for i in fields.size():
				data[fields[i]] = values[i]
		if data.is_empty():
			dao.values(values)
		else:
			dao.values(data)
		return dao
	else:
		return _assert_false("Sql should begin with one of [SELECT, UPDATE, DELETE, INSERT, REPLACE].")
		
static func parse_select(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_select.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	if ret.is_empty():
		return _assert_false("Cannot parse your SELECT sql.")
	if ret.size() < 2:
		return _assert_false("SELECT need at least SELECT and FROM.")
	if ret[0][1] == "":
		return _assert_false("Missing fields after SELECT.")
	if ret[1][0].to_upper() != "FROM":
		return _assert_false("Missing FROM after SELECT.")
	return ret
	
static func parse_update(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_update.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	if ret.is_empty():
		return _assert_false("Cannot parse your UPDATE sql.")
	if ret[1][0].to_upper() != "SET":
		return _assert_false("Missing SET after UPDATE.")
	if ret.size() > 3:
		return _assert_false("Redundant info near: [%s]" % ret[3][0] if ret.size() > 3 else "")
	return ret
	
static func parse_delete(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var matches = re_delete.search_all(prepare[0])
	var ret = []
	for i: RegExMatch in matches:
		ret.push_back([i.get_string(1), restore(i.get_string(2).strip_edges(), prepare[1])])
	ret = _check_semicolon(ret)
	if ret.is_empty():
		return _assert_false("Cannot parse your DELETE sql.")
	if ret.size() > 2:
		return _assert_false("Cannot parse your DELETE sql.")
	if not (ret[0][0].countn("delete") == 1 and ret[0][0].countn("from") == 1):
		return _assert_false("Cannot parse your DELETE sql.")
	if ret.size() == 2 and not ret[1][0].strip_edges().to_upper() == "WHERE":
		return _assert_false("Cannot parse your DELETE sql.")
	return ret
	
static func parse_insert(sql: String) -> Array:
	#var prepare = prepare_sql(sql)
	#var rm = prepare[1]
	var m = re_insert.search(sql)
	var ret
	if m:
		ret = [
			m.get_string(1).strip_edges(), # insert into
			m.get_string(2).strip_edges(), # db.table
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			m.get_string(5).strip_edges(), # (1,2,3)
			m.get_string(6).strip_edges(), # on duplicate key update
			m.get_string(7).strip_edges(), # xxx
		]
		ret = _check_semicolon(ret)
	if ret == null or ret.is_empty():
		return _assert_false("Cannot parse your INSERT sql.")
	if ret[3].to_upper() != "VALUES":
		return _assert_false("Parser error of keyword VALUES.")
	if ret[5] != "":
		if ret[5].countn("duplicate") == 0:
			return _assert_false("Parser error of keyword ON DUPLICATE KEY UPDATE.")
	return ret
	
static func parse_replace(sql: String) -> Array:
	var prepare = prepare_sql(sql)
	var rm = prepare[1]
	var m = re_replace.search(prepare[0])
	var ret
	if m:
		ret = [
			m.get_string(1).strip_edges(), # replace into
			restore(m.get_string(2).strip_edges(), rm), # db.table
			m.get_string(3).strip_edges(), # (x,y,z)
			m.get_string(4).strip_edges(), # values
			restore(m.get_string(5).strip_edges(), rm), # (1,2,3)
		]
		ret = _check_semicolon(ret)
	if ret == null or ret.is_empty():
		return _assert_false("Cannot parse your REPLACE sql.")
	if ret[3].to_upper() != "VALUES":
		return _assert_false("Parser error of keyword VALUES.")
	return []
	
static func prepare_sql(sql: String) -> Array:
	sql = sql.strip_edges()
	var quoted_matches = GDSQL.GDSQLUtils.extract_outer_quotes(sql)
	var replacements = {}
	var index = -1
	for i in quoted_matches:
		index += 1
		var r = "___Rep%d___" % index
		while sql.contains(r):
			index += 1
			r = "___Rep%d___" % index
		replacements[r] = i
		sql = sql.replace(i, r)
	return [sql, replacements]
	
static func restore(s: String, map: Dictionary) -> String:
	if not s.contains("___Rep"):
		return s
	for k in map:
		s = s.replace(k, map[k])
	return s
	
## 可能的返回值：
## 0. String
## 1. QueryResult
## 2. {"sql": String(expression), ___Rep0___: QeuryResult, ___Rep1___: {"sql": String, ...}}
static func replace_nested_sql_expression(expression: String, 
sql_input_names: Dictionary = {}, sql_static_inputs: Array = [], 
sql_varying_inputs: Dictionary = {}, need_user_enter_password: Array = []):
	var dp = lru_cache.get_value(expression)
	if dp == null:
		dp = deep_prepare_sql(expression)
		lru_cache.put_value(expression, dp)
		
	if dp.is_empty():
		return expression
	var ret = _simplify_expression(dp.duplicate(), sql_input_names, sql_static_inputs, 
		sql_varying_inputs, need_user_enter_password)
	return ret
	
static func _simplify_expression(info, sql_input_names: Dictionary = {}, 
sql_static_inputs: Array = [], sql_varying_inputs: Dictionary = {}, 
need_user_enter_password: Array = []):
	if info is String:
		if info.length() > 6 and info.countn("select", 0, 6) > 0 and info[6].strip_edges() == "":
			var input_names = [] # 补充表名
			var inputs = [] # 补充数据
			# sql_input_names 的结构：
			# {
			#     'x': {
			#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
			#         false: index,		# false表示x是一个补充表名（来自__input_names）
			#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
			#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
			#     }
			# }
			for t in sql_input_names:
				if sql_input_names[t].has(true):
					# 外部可能传入空字典，表示暂时没数据，那么当作缺表处理，会
					# 体现在下面dao的执行结果中。
					if sql_varying_inputs.is_empty():
						continue
					input_names.push_back(t)
					inputs.push_back(sql_varying_inputs[t])
					continue
				if sql_input_names[t].has(false):
					if not input_names.has(t): # 优先级低于普通表名
						input_names.push_back(t)
						inputs.push_back(sql_static_inputs[sql_input_names[t][false]])
				# NOTICE 不管字段，因为inputs里包含了字段的数据，在子查询dao里，会自己重新构造input_names结构
				
			var dao = lru_cache.get_value(["dao", info])
			if dao == null:
				dao = parse_to_dao(info)
				lru_cache.put_value(["dao", info], dao)
			dao.set_input_names(input_names)
			dao.set_inputs(inputs)
			dao.set_collect_lack_table_mode(true)
			dao.set_need_head(false)
			var res = dao.query() # 当sql中存在依赖其他表数据的情况时，res QueryResult的标志lack_data是true
			if dao.need_user_enter_password():
				need_user_enter_password.push_back(true)
			else:
				if not res is GDSQL.QueryResult:
					return _assert_false("Error occur!")
			return res
		return info
	else:
		for k in info.keys():
			if info[k] is GDSQL.QueryResult:
				continue
			if k != "sql":
				info[k] = _simplify_expression(info[k], sql_input_names, 
					sql_static_inputs, sql_varying_inputs, need_user_enter_password)
				if not need_user_enter_password.is_empty():
					return null
		return info
		
## WARNING expression cannot be "xxx" + "yyy" or 'xxx' + 'yyy'
static func deep_prepare_sql(expression: String, origin: String = "", p_index: Array = [-1]):
	if origin == "":
		origin = expression
	var ret = {}
	var e = _remove_outer_quotes(expression.strip_edges())
	var sql2 = e[1]
	if not (sql2.length() > 6 and sql2.contains("select")):
		return ret
	var quoted_matches = GDSQL.GDSQLUtils.extract_outer_quotes(sql2)
	for i in quoted_matches:
		if i.begins_with("'") or i .begins_with('"'):
			continue
		p_index[0] += 1
		var r = "___Rep%d___" % p_index[0]
		while origin.contains(r):
			p_index[0] += 1
			r = "___Rep%d___" % p_index[0]
		var ee = _remove_outer_quotes(i.strip_edges())
		var sets = _get_value_list(ee[1], false)
		for j in sets:
			var info = deep_prepare_sql(j, origin, p_index)
			if not info.is_empty():
				sql2 = sql2.replace(j, r)
				ret.sql = sql2
				ret[r] = info
	if ret.is_empty():
		return sql2
	return ret
	
## 检查有没有多余的分号
static func _check_semicolon(ret: Array) -> Array:
	if ret.is_empty():
		return ret
	for i in ret.size()-1:
		if ret[i] is Array:
			for j in ret[i].size():
				if ret[i][j].ends_with(";"):
					return _assert_false(
					"Invalid semicolon found near [%s]" % ret[i][j])
		else:
			if ret[i].ends_with(";"):
				return _assert_false("Invalid semicolon found near [%s]" % ret[i])
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
	if splits.size() != 2:
		return _assert_false("Wrong table format. Near [%s]." % s)
	return [splits[0].strip_edges(), splits[1].strip_edges()]
	
static func _get_db_table_alias(s: String) -> Array[String]:
	var db = s.get_slice(".", 0).strip_edges() if s.contains(".") else ""
	var table = s.get_slice(".", 1).strip_edges()
	var alias = ""
	table = table.replace("\t", " ")
	if table.contains(" "):
		var splits = table.split(" ", false)
		if splits.size() != 2:
			return _assert_false("Wrong table and alias. Near [%s]." % table)
		table = splits[0]
		alias = splits[1]
	return [db, table, alias]
	
## 去掉最外层括号
static func _extract_bracket(s: String) -> String:
	if s.begins_with("(") and s.ends_with(")"):
		s = s.substr(1, s.length()-2)
	return s
	
static func _remove_outer_quotes(s: String) -> Array:
	var begin = ""
	var end = ""
	while true:
		if s.begins_with("(") and s.ends_with(")"):
			s = s.substr(1, s.length()-2)
			begin += "("
			end = ")" + end
		elif s.begins_with("[") and s.ends_with("]"):
			s = s.substr(1, s.length()-2)
			begin += "["
			end = "]" + end
		elif s.begins_with("{") and s.ends_with("}"):
			s = s.substr(1, s.length()-2)
			begin += "{"
			end = "}" + end
		elif s.begins_with("'") and s.ends_with("'"):
			s = s.substr(1, s.length()-2)
			begin += "'"
			end = "'" + end
		elif s.begins_with('"') and s.ends_with('"'):
			s = s.substr(1, s.length()-2)
			begin += '"'
			end = '"' + end
		else:
			break
	return [begin, s, end]
	
#static func _extract_quote(s: String) -> String:
	#if s.begins_with("'") and s.begins_with("'"):
		#s = s.substr(1, s.length()-2)
	#elif s.begins_with('"') and s.begins_with('"'):
		#s = s.substr(1, s.length()-2)
	#return s
	
## 不考虑非常规field名称，比如带引号的
static func _get_field_list(s: String) -> Array[String]:
	s = _extract_bracket(s)
	var splits = s.split(",")
	var ret = [] as Array[String]
	for i in splits:
		ret.push_back(i.strip_edges())
	return ret
	
## 获取逗号分隔的值列表。逗号在括号和引号内的不会分隔。
static func _get_value_list(s: String, evaluate: bool) -> Array:
	s = _extract_bracket(s)
	var matches = re_split_comma.search_all(s)
	var ret = []
	if not matches.is_empty():
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var value = s.substr(start, i.get_start() - start).strip_edges()
			if evaluate:
				value = _get_var(value)
			ret.push_back(value)
			start = i.get_end()
			
		# 别忘了还有最后一个逗号到最后
		if start < s.length():
			var value = s.substr(start).strip_edges()
			if evaluate:
				value = _get_var(value)
			ret.push_back(value)
	else:
		if evaluate:
			var value = _get_var(s)
			ret.push_back(value)
		else:
			ret.push_back(s)
	return ret
	
## deal column1 = xxx
static func _get_set_value(s: String) -> Array:
	var m = re_split_equal.search(s)
	if not m:
		return _assert_false("Error near: [%s]" % s)
	var first = s.substr(0, m.get_start()).strip_edges()
	var second = s.substr(m.get_end()).strip_edges()
	#return [first, _get_var(second)] # 由于数据不全（有些数据在数据库），不能在这里evaluate。
	return [first, second]
	
## deal column1 = call_('1', \"abc\"), column2 = value2
static func _get_set_value_list(s: String) -> Dictionary:
	var sets = _get_value_list(s, false) # 先逗号分开
	var ret = {}
	for i in sets:
		var splits = _get_set_value(i)
		if not splits:
			return {}
		if ret.has(splits[0]):
			return _assert_false("Duplicate set field near: [%s]" % s)
		ret[splits[0]] = splits[1]
	return ret
	
## deal b=values(xxx)
static func _get_field_value(s: String) -> Array[String]:
	var m = re_field_value.search(s)
	if m:
		return [m.get_string(1), m.get_string(2)]
	return []
	
static func _get_var(s: String):
	var try = str_to_var(s)
	if typeof(try) == TYPE_NIL:
		try = GDSQL.GDSQLUtils.evaluate_command(null, s)
	if typeof(try) == TYPE_NIL:
		return s
	return try
	
class SQLParserCacheNode extends RefCounted:
	var key
	var value: Variant
	var prev: SQLParserCacheNode
	var next: SQLParserCacheNode
	
class SQLParserLRULink extends RefCounted:
	var cache: Dictionary
	var capacity: int
	var head: SQLParserCacheNode = SQLParserCacheNode.new()
	var tail: SQLParserCacheNode = SQLParserCacheNode.new()
	
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if head:
				head.next = null
				head = null
			if tail:
				tail.prev = null
				tail = null
				
	func _init() -> void:
		head.next = tail
		tail.prev = head
		
	func has_key(key) -> bool:
		return cache.has(key)
		
	func get_value(key):
		if not cache.has(key):
			return null
		var node = cache[key] as SQLParserCacheNode
		move_to_tail(node)
		return node.value
		
	func remove_value(key):
		if not has_key(key):
			return
		var node = cache[key] as SQLParserCacheNode
		remove_node(node)
		cache.erase(key)
		
	func put_value(key, value: Variant):
		if cache.has(key):
			var node = cache[key] as SQLParserCacheNode
			node.value = value
			move_to_tail(node)
		else:
			var node = SQLParserCacheNode.new()
			node.key = key
			node.value = value
			
			# 添加节点到链表尾部  
			add_to_tail(node)
			
			# 将新节点添加到哈希表中  
			cache[key] = node
			
			# 如果超出容量，删除最久未使用的节点  
			if cache.size() > capacity:
				var removed_node = remove_head()
				cache.erase(removed_node.key)
				
	func add_to_tail(node: SQLParserCacheNode):
		var prev_node = tail.prev
		prev_node.next = node
		node.prev = prev_node
		node.next = tail
		tail.prev = node
		
	func remove_node(node: SQLParserCacheNode):
		var prev_node = node.prev
		var next_node = node.next
		prev_node.next = next_node
		next_node.prev = prev_node
		
	func move_to_tail(node: SQLParserCacheNode):
		remove_node(node)
		add_to_tail(node)
		
	func remove_head():
		var head_next = head.next
		remove_node(head_next)
		return head_next
		
	func clear():
		# 清空双向链表
		var current = head.next
		while current != tail:
			var next_node = current.next
			# 从哈希表中移除当前节点的键  
			cache.erase(current.key)
			# 断开当前节点的连接  
			current.prev = null
			current.next = null
			# 移动到下一个节点  
			current = next_node
			
		# 双向链表重置为只有一个头节点和尾节点  
		head.next = tail
		tail.prev = head
		
	func clean():
		clear()
		head.next = null
		tail.prev = null
		head = null
		tail = null
		
