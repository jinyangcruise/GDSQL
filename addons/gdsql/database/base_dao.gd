@tool
extends RefCounted

#region Members
var _PASSWORD = "" ## 数据表密码

var __request_password: Array ## 【外部请勿使用】query过程中是否请求密码（只存在于编辑器模式下）
var __db_path = "" ## 【外部请勿使用】数据库路径
var __db_name: String = ""  ## 【外部请勿使用】数据库名称
var __cmd: String = "" ## 【外部请勿使用】命令
var __select_str = "" ## 【外部请勿使用】select字符串
var __select: Array[String] = [] ## 【外部请勿使用】select哪些字段
var __field_as_index: Dictionary = {} ## 【外部请勿使用】字段别名的位置索引
var __table: String = "" ## 【外部请勿使用】表名（带extension的）
var __table_alias: String = "" ## 【外部请勿使用】别名
var __data ## Dictionary or Array ## 【外部请勿使用】更新数据使用
var __where: Array = [] ## 【外部请勿使用】筛选数据条件
var __group_by: Array = [] ## 【外部请勿使用】数据分组依据，支持列别名
var __order_by: Array = [] ## 【外部请勿使用】排序条件，支持列别名
var __offset: int = -1 ## 【外部请勿使用】select返回数据截取起始位置
var __limit: int = -1 ## 【外部请勿使用】select返回数据截取长度
var __duplicate_update_fields: Array = [] ## 【外部请勿使用】主键重复时更新哪些字段
var __primary_key: String = "" ## 【外部请勿使用】主键是什么
var __primary_key_def: String = "" ## 【外部请勿使用】定义文件中的主键
var __autoincrement_keys: Dictionary = {} ## 【外部请勿使用】自增键有哪些
var __autoincrement_keys_def: Dictionary = {} ## 【外部请勿使用】定义文件中的自增键
var __union_all: GDSQL.BaseDao ## 【外部请勿使用】union的单元
var __parent_union: WeakRef ## 【外部请勿使用】被uion的单元
#var __left_join_tables: Dictionary = {} ## 【外部请勿使用】联表查询的表相关信息
var __left_join: GDSQL.LeftJoin ## 【外部请勿使用】第一个联表对象（获取第N个联表对象需要通过第N-1个联表对象来获取）
var __need_post_porcess: bool = true ## 【外部请勿使用】select最终返回数据时处理：是否按照用户所需的字段进行精简
var __need_head: bool ## 【外部请勿使用】select返回的数据是否包含一行表头（在第一行）
var __auto_commit: bool = true ## 【外部请勿使用】自动提交标志
#var __table_conf_path: Dictionary = {} ## 【外部请勿使用】临时为了获取数据库定义文件
var __enable_evaluate: bool = false ## 【外部请勿使用】当update或insert、replace时，是否对值进行evaluate操作
var __sub_select_index: int = -1 ## 【外部请勿使用】子查询序号
var __select_query_columns_count: int = 0 ## 【外部请勿使用】select时，结果的列数
var __sub_queries: Dictionary ## 【外部请勿使用】语句中的子查询，例如: select * from t where 1 == __SQL__
var __input_names: Array ## 【外部请勿使用】额外的表名，补充表名
# {
#     'x': {
#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
#         false: index,		# false表示x是一个补充表名（来自__input_names）
#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
#     }
# }
var __final_input_names: Dictionary ## 【外部请勿使用】最终表达式输入名
var __inputs: Array ## 【外部请勿使用】额外的表数据，和__input_names一一对应
var __lack_table: Array ## 【外部请勿使用】query时，缺少的外部表的名称（alias），
						## 子查询中的alias可能和主查询、其他子查询使用相同的alias
var __collect_lack_table_enabled: bool = false ## 【外部请勿使用】是否开启收集缺表数据模式
var __err = []

## 匹配逗号的位置，括号、引号内的逗号都不匹配
#static var regex_comma: RegEx = RegEx.new()
## 匹配field alias
static var regex_as: RegEx = RegEx.new()
## sysbol
static var regex_symbol: RegEx = RegEx.new()

static var lru_cache: ExpressionLRULink

var regex_field_map: Dictionary

const DEK = "_DEK_"

const PRIMARY_TYPES = [TYPE_INT, TYPE_STRING, TYPE_STRING_NAME]
const NORMAL_TYPES = [
	TYPE_NIL, TYPE_BOOL,
	#TYPE_INT,
	TYPE_FLOAT,
	#TYPE_STRING,
	TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I,
	TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D,
	TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION,
	TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION,
	TYPE_COLOR,
	#TYPE_STRING_NAME,
	TYPE_NODE_PATH, TYPE_RID,
	#TYPE_OBJECT,
	TYPE_CALLABLE, TYPE_SIGNAL, TYPE_DICTIONARY, TYPE_ARRAY,
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY,
	TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY,
]

var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager
#endregion


static func _static_init():
	lru_cache = ExpressionLRULink.new()
	lru_cache.capacity = 1024
	#regex_comma.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	regex_as.compile("([\\s]+)(as[\\s]+)?([0-9a-zA-Z_:]+)$") # 支持 x as position:x 这样的写法
	regex_symbol.compile("[a-zA-Z_]+[0-9a-zA-Z_]*")
	
func set_collect_lack_table_mode(enable: bool) -> GDSQL.BaseDao:
	__collect_lack_table_enabled = enable
	return self
	
## 使用某个数据库。传入数据库名称。
func use_db_name(database_name: String) -> GDSQL.BaseDao:
	database_name = GDSQL.RootConfig.validate_name(database_name)
	__db_name = database_name
	__db_path = GDSQL.RootConfig.get_database_data_path(__db_name)
	return self
	
## 使用某个数据库。可以传入数据库名称或数据库的数据路径。系统自动判断传入的是数据库名称还是数据库路径。
func use_db(database_name_or_path: String) -> GDSQL.BaseDao:
	if database_name_or_path.contains("/"):
		__db_path = database_name_or_path
		__db_name = GDSQL.RootConfig.get_database_name_by_db_path(__db_path)
	else:
		database_name_or_path = GDSQL.RootConfig.validate_name(database_name_or_path)
		__db_name = database_name_or_path
		__db_path = GDSQL.RootConfig.get_database_data_path(__db_name)
	return self
	
func use_user_db() -> GDSQL.BaseDao:
	use_db("user://")
	return self
	
func use_conf_db() -> GDSQL.BaseDao:
	var game_conf_db_dir = GDSQL.get_setting_game_conf_db_dir()
	if game_conf_db_dir == "":
		return _assert_false("use_conf_db", "Game conf db dir is not set!")
	use_db(game_conf_db_dir)
	return self
	
func get_db() -> String:
	return __db_name
	
func set_password(password) -> GDSQL.BaseDao:
	_PASSWORD = password
	return self
	
func get_password():
	return _PASSWORD
	
## 是否自动提交（保存文件），不提交只是在内存中更改数据
func auto_commit(auto: bool) -> GDSQL.BaseDao:
	__auto_commit = auto
	return self
	
func _assert_false(action: String, msg: String):
	if mgr and Engine.is_editor_hint():
		mgr.create_accept_dialog(msg)
		mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(), action, msg)
	push_error(msg)
	__err.push_back(msg)
	assert(false, msg)
	return null
	
func _get_conf(db_name: String, table_name: String, password, indexed_names = []) -> GDSQL.ImprovedConfigFile:
	var defination = __get_table_defination(db_name, table_name)
	var valid_if_not_exist = defination["valid_if_not_exist"] if defination else false
	var path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
	if valid_if_not_exist:
		GDSQL.ConfManager.mark_valid_if_not_exit(path)
	var conf = GDSQL.ConfManager.get_conf(path, password)
	if conf:
		if not indexed_names.is_empty():
			conf.set_indexed_props(indexed_names)
	return conf
	
## 手动提交（保存到文件）
func commit() -> void:
	if not __db_name or not __db_path:
		_assert_false("commit", "database is empty")
		return
	if __table == "":
		_assert_false("commit", "table name is empty")
		return
	var path = __db_path.path_join(__table)
	var conf: GDSQL.ImprovedConfigFile = _get_conf(__db_name, __table, _PASSWORD)
	if conf == null:
		_assert_false("commit", "load conf err!")
		return
	GDSQL.ConfManager.save_conf_by_origin_password_or_dek(path)
	reset()
	
## 抛弃修改（没有commit时使用才有效果）
func discard() -> void:
	if not __db_name or not __db_path:
		_assert_false("commit", "database is empty")
		return
	if __table == "":
		_assert_false("commit", "table name is empty")
		return
	var path = __db_path.path_join(__table)
	GDSQL.ConfManager.remove_conf(path)
	
## 开启求值操作。仅在update操作时有效。仅在值为字符串时进行取值
func set_evalueate_mode(enable: bool):
	__enable_evaluate = enable
	
## 查询数据子句
## something: 查询字段语句，即数据库查询语句select和from之间的语句
## need_head: 是否需要表头。传true，如果查询到了数据，那么返回数据的第一行会是一个表头表示每列是什么字段。
## union表该参数无效，等价于false。
## 注意：若联表查询还要求返回平数据，则query后会在每条数据的每个字段前加上表的别名和小数点。例如：
## [["t1.a": xx, "t2.m": yy]].
## 这个方法会预处理每个要求的字段和字段的别名（如有），但不会马上在这里处理星号，而是推迟到query的时候才处理。
func select(something: String, need_head: bool) -> GDSQL.BaseDao:
	if not (__cmd == "" or __cmd == "select"):
		return _assert_false("select", "already set command %s" % __cmd)
	#if __parent_union and need_head:
		#push_warning("union table cannot have head but the param `need_head` is true, 
		#this param will be ignored")
	__cmd = "select"
	__select_str = something
	__select.clear()
	__field_as_index.clear()
	__need_head = need_head
	something = something.strip_edges()
	# 拆分select的字段。不能简单用split(",")，因为字段有可能是函数调用，它不支持正则（至少Godot 4.1不支持）
	# 下面的方案支持类似这样的情况："*,a.uname.contains(),aa.level, t.img, at.icon(1, 2, \"a, b\"), 
	# t_user.u, y.call()"
	#var regex = RegEx.new()
	#regex.compile(",\\s*(?![^()]*\\))") # 匹配逗号的位置，括号内的逗号不匹配
	# 匹配逗号的位置，括号、引号内的逗号都不匹配
	#regex.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	#var matches = regex_comma.search_all(something)
	var matches = GDSQL.GDSQLUtils.search_symbol(something, ",")
	
	# 别名
	#var regex_2 = RegEx.new()
	#regex_2.compile("[\\s]+as[\\s]+([0-9a-zA-Z_]+)$")
	#regex_2.compile("([\\s]+)(as[\\s]+)?([0-9a-zA-Z_:]+)$") # 支持 x as position:x 这样的写法
	
	if not matches.is_empty():
		
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var field_str = something.substr(start, i[0] - start).strip_edges()
			var field_as = ""
			start = i[1]
			
			# 有可能取了别名，例如t_user.icon(1, 2, \"a, b\") as iii
			var m = regex_as.search(field_str)
			if m:
				# 实际要求的式子，例子中的t_user.icon(1, 2, \"a, b\")
				field_str = field_str.substr(0, m.get_start(1))
				field_as = m.get_string(3)
				
			__field_as_index[__select.size()] = field_as
			__select.push_back(field_str)
			
		# 别忘了还有最后一个逗号到最后
		if start < something.length():
			var field_str = something.substr(start).strip_edges()
			var field_as = ""
			
			var m = regex_as.search(field_str)
			# t. name 或别的运算符也会匹配上，所以还需要检查前面那个符号是不是运算符
			if m and not field_str[m.get_start(1)-1] in ".+-*/&^%<>|!~":
				field_str = field_str.substr(0, m.get_start(1))
				field_as = m.get_string(3)
				
			__field_as_index[__select.size()] = field_as
			__select.push_back(field_str)
	# 没有逗号分割，*或者某个单独的字段
	else:
		var field_as = ""
		var m = regex_as.search(something)
		if m and not something[m.get_start(1)-1] in ".+-*/&^%<>|!~":
			something = something.substr(0, m.get_start(1))
			field_as = m.get_string(3)
			
		__field_as_index[__select.size()] = field_as
		__select.push_back(something)
	return self
	
## union之后的BaseDao可以进行select_same，表示与父BaseDao查询相同的字段。
## 该方法是为了简化用户输入。
func select_same() -> GDSQL.BaseDao:
	if __parent_union == null:
		return _assert_false("select_same", "must have parent union!")
	if __cmd != "":
		return _assert_false("select_same", "already set command %s" % __cmd)
	__cmd = "select"
	__select_str = __parent_union.get_ref().__select_str
	__select = __parent_union.get_ref().__select.duplicate()
	__field_as_index = __parent_union.get_ref().__field_as_index.duplicate()
	__need_head = false
	return self
	
## select是否需要表头
func set_need_head(p_need_head: bool) -> GDSQL.BaseDao:
	__need_head = p_need_head
	return self
	
## 同时设置表名和别名。table支持不带后缀和带后缀.gsql
func from(table: String, alias: String = "") -> GDSQL.BaseDao:
	table = GDSQL.RootConfig.validate_name(table)
	if not table.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
		table = table + GDSQL.RootConfig.DATA_EXTENSION
	__table = table
	__table_alias = alias
	return self
	
func _set_primary_and_autoincre():
	if __db_name and __db_path and __table and __table != GDSQL.RootConfig.DATA_EXTENSION:
		__primary_key_def = ""
		__autoincrement_keys_def = {}
		var defination = __get_table_defination(__db_name, __table)
		if defination != null and !defination.is_empty():
			for column in defination["columns"]:
				if column["PK"]:
					__primary_key_def = column["Column Name"]
					__primary_key = __primary_key_def
				if column["AI"]:
					__autoincrement_keys_def[column["Column Name"]] = 0
					
## 单独设置表名
func set_table(table: String) -> GDSQL.BaseDao:
	from(table, __table_alias)
	return self
	
func get_table() -> String:
	return __table
	
func get_short_table() -> String:
	return get_table().get_file().get_basename()
	
## 单独设置表别名
func set_table_alias(alias: String) -> GDSQL.BaseDao:
	__table_alias = alias
	return self
	
## data is Array or Dictionary
func values(data) -> GDSQL.BaseDao:
	if not (__cmd.begins_with("insert") or __cmd.begins_with("replace")):
		return _assert_false("values", 
		"'values' can only be used after 'insert' or 'replace'")
	__data = data
	return self
	
func sets(data: Dictionary) -> GDSQL.BaseDao:
	if __cmd != "update":
		return _assert_false("sets", "'sets' can only be used after 'update'")
	__data = data
	return self
	
func insert_into(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("insert_into", "already set command %s" % __cmd)
	__cmd = "insert_into"
	set_table(table)
	return self
	
func insert_ignore(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("insert_ignore", "already set command %s" % __cmd)
	__cmd = "insert_ignore"
	set_table(table)
	return self
	
func insert_or_update(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("insert_or_update", "already set command %s" % __cmd)
	__cmd = "insert_or_update"
	set_table(table)
	return self
	
func replace_into(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("replace_into", "already set command %s" % __cmd)
	__cmd = "replace_into"
	set_table(table)
	return self
	
func update(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("update", "already set command %s" % __cmd)
	if __table_alias != "":
		return _assert_false("update", "table alias must be empty")
	__cmd = "update"
	set_table(table)
	return self
	
func delete_from(table: String) -> GDSQL.BaseDao:
	if __cmd != "":
		return _assert_false("delete_from", "already set command %s" % __cmd)
	__cmd = "delete_from"
	set_table(table)
	return self
	
## 如果多次调用，那么这些条件将是`and`的关系。如需避免多次调用，请使用set_where。
## 如果是union的，那么where作用于最终数据集上，也就是第一个BaseDao上。
func where(cond: String) -> GDSQL.BaseDao:
	if not (__cmd == "select" or __cmd == "update" or __cmd == "delete_from"):
		return _assert_false("where", 
		"'where' can only be used after 'select' or 'update' or 'delete_from'")
	cond = cond.strip_edges()
	if cond != "":
		__where.push_back(cond)
	return self
	
func set_where(cond: String) -> GDSQL.BaseDao:
	if __parent_union:
		__parent_union.get_ref().set_where(cond)
		return self
	if not (__cmd == "select" or __cmd == "update" or __cmd == "delete_from"):
		return _assert_false("where", 
		"'where' can only be used after 'select' or 'update' or 'delete_from'")
	cond = cond.strip_edges()
	__where.clear()
	if cond != "":
		__where.push_back(cond)
	return self
	
## 返回一个新的baseDao
func union_all() -> GDSQL.BaseDao:
	if __cmd != "select":
		return _assert_false("union_all", "'union_all' can only be used after 'select'")
	var bd = GDSQL.BaseDao.new()
	__union_all = bd
	bd.set_collect_lack_table_mode(__collect_lack_table_enabled)
	bd.__parent_union = weakref(self)
	return bd
	
## 是否uionall了
func is_union_all() -> bool:
	return not (__union_all == null and __parent_union == null)
	
## 设置unionall对象，返回的仍旧是自己
func set_union_all(base_dao: GDSQL.BaseDao) -> GDSQL.BaseDao:
	if __cmd != "select":
		return _assert_false("set_union_all", "'union_all' can only be used after 'select'")
	__union_all = base_dao
	base_dao.__parent_union = weakref(self)
	return self
	
func remove_union_all(base_dao: GDSQL.BaseDao) -> bool:
	if __union_all == base_dao:
		__union_all.__parent_union = null
		__union_all = null
		return true
	return false
	
func has_union_all(base_dao: GDSQL.BaseDao) -> bool:
	return __union_all == base_dao
	
## 聚合分组。支持多个字段，用逗号分隔。
func group_by(something: String) -> GDSQL.BaseDao:
	if __cmd != "select":
		return _assert_false("order_by", "'order_by' can only be used after 'select'")
	something = something.strip_edges()
	if something == "":
		return self
	#__group_by = Array(fields.split(",")) NOTICE 过于粗糙，改为下面的逻辑
	#var matches = regex_comma.search_all(something)
	var matches = GDSQL.GDSQLUtils.search_symbol(something, ",")
	if not matches.is_empty():
		var start = 0
		for i in matches:
			var field_str = something.substr(start, i[0] - start).strip_edges()
			start = i[1]
			__group_by.push_back(field_str)
			
		if start < something.length():
			var field_str = something.substr(start).strip_edges()
			__group_by.push_back(field_str)
	else:
		__group_by.push_back(something)
	return self
	
## 注意，若用该方法，就一次性传入字符串。如果多次使用，只有最后一次的有效。
func group_by_str(something: String) -> GDSQL.BaseDao:
	if __cmd != "select":
		return _assert_false("group_by_str", "'group by' can only be used after 'select'")
	__group_by.clear()
	return group_by(something)
	
## 注意该方法具有嵌套效果，在union的时候，链条中某个环节的order_by会对后面所有环节进行排序
## 如果是union的，那么order by作用于最终数据集上。
func order_by(field: String, order: GDSQL.ORDER_BY = GDSQL.ORDER_BY.ASC) -> GDSQL.BaseDao:
	if __parent_union:
		__parent_union.get_ref().order_by(field, order)
		return self
	if __cmd != "select":
		return _assert_false("order_by", "'order_by' can only be used after 'select'")
	field = field.strip_edges()
	if field != "":
		__order_by.push_back([field, order])
	return self
	
## 注意，若用该方法，就一次性传入字符串。如果多次使用，只有最后一次的有效。
func order_by_str(string: String) -> GDSQL.BaseDao:
	if __parent_union:
		__parent_union.get_ref().order_by_str(string)
		return self
	if __cmd != "select":
		return _assert_false("order_by_str", "'order_by' can only be used after 'select'")
	if string.strip_edges() == '':
		__order_by.clear()
		return self
	# 清空
	__order_by.clear()
	#var regex = RegEx.new()
	# 匹配逗号的位置，括号、引号内的逗号都不匹配
	#regex.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	#var matches = regex_comma.search_all(string)
	var matches = GDSQL.GDSQLUtils.search_symbol(string, ",")
	var arr = []
	if not matches.is_empty():
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var a_order = string.substr(start, i[0] - start).strip_edges()
			arr.push_back(a_order)
			start = i[1]
			
		# 别忘了还有最后一个逗号到最后
		if start < string.length():
			var a_order = string.substr(start).strip_edges()
			arr.push_back(a_order)
	else:
		arr.push_back(string)
		
	for a_order: String in arr:
		a_order = a_order.strip_edges()
		var l = a_order.length()
		var find = false
		if l > 4 and (a_order.contains(" ") or \
		a_order.contains("\t") or a_order.contains("\n")):
			if l > 5:
				if a_order.countn(" desc", l - 5) > 0 or \
				a_order.countn("\tdesc", l - 5) > 0 or \
				a_order.countn("\ndesc", l - 5) > 0:
					__order_by.push_back([a_order.substr(0, l - 5).strip_edges(), GDSQL.ORDER_BY.DESC])
					find = true
			if not find:
				if a_order.countn(" asc", l - 4) > 0 or \
				a_order.countn("\tasc", l - 4) > 0 or \
				a_order.countn("\nasc", l - 4) > 0:
					__order_by.push_back([a_order.substr(0, l - 4).strip_edges(), GDSQL.ORDER_BY.ASC])
					find = true
		if not find:
			__order_by.push_back([a_order, GDSQL.ORDER_BY.ASC])
			
	return self
	
## 注意该方法具有嵌套效果，在union的时候，链条中某个环节的limit会对后面所有环节进行limit
func limit(a_offset: int, a_limit: int) -> GDSQL.BaseDao:
	if __cmd != "select":
		return _assert_false("limit", "'limit' can only be used after 'select'")
	if a_offset < 0 or a_limit <= 0:
		return _assert_false("limit", "offset must not less than 0 and limit must larger than 0")
	__offset = a_offset
	__limit = a_limit
	return self
	
func on_duplicate_update(fields: Array[String]) -> GDSQL.BaseDao:
	if not (__cmd == "update" or __cmd == "insert_or_update"):
		return _assert_false("on_duplicate_update", 
		"'on_duplicate_update' can only be used after 'update' or 'insert_or_update'")
	__duplicate_update_fields = fields
	return self
	
## 指定主键（适用于没有定义文件的表。如果表有定义文件，则勿设置其他键为主键。）
func primary_key(a_key: String, auto_increment: bool = true) -> GDSQL.BaseDao:
	if not (__primary_key_def == "" or a_key == __primary_key_def):
		return _assert_false("primary_key", 
		"this table has defination of primary key, do not set a different primary key")
	__primary_key = a_key
	if auto_increment:
		__autoincrement_keys[a_key] = 0
	return self
	
## 增加自增字段
## 注意1：如果用户自己设定了某个非主键自增字段的值，则按用户设置的值为准，不会自增；
## 注意2：如果用户命令是insert_or_update，只有在新增数据的情况下才可能（也关系到注意1的情况）自增
## 注意3：如果操作的表的定义文件中该字段并非自增字段，不影响本次操作临时把其当成自增字段。
func add_auto_increment_key(a_key: String) -> GDSQL.BaseDao:
	if not (__cmd.begins_with("insert") or __cmd.begins_with("replace")):
		return _assert_false("add_auto_increment_key", 
		"'add_auto_increment_key' can only be used after 'insert' or 'replace'")
	__autoincrement_keys[a_key] = 0
	return self
	
func left_join(db_name: String, table: String, alias: String, cond: String, password: String) -> GDSQL.BaseDao:
	if not __cmd.begins_with("select"):
		return _assert_false("left_join", "left_join must use after select")
	if __table_alias == "":
		return _assert_false("left_join", "main table must have alias name before use 'left join'")
	if not (alias != __table_alias and (__left_join == null or not __left_join.chain_has_alias(alias))):
		return _assert_false("left_join", "duplicate table alias")
	if db_name == "":
		db_name = __db_name
	if not table.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
		table = table + GDSQL.RootConfig.DATA_EXTENSION
		
	var left_join_obj: GDSQL.LeftJoin
	if __left_join == null:
		__left_join = GDSQL.LeftJoin.new()
		left_join_obj = __left_join
	else:
		left_join_obj = __left_join.create_left_join_to_end()
	left_join_obj.set_db(db_name)
	left_join_obj.set_password(password)
	left_join_obj.set_table(table)
	left_join_obj.set_alias(alias)
	left_join_obj.set_condition(cond)
	return self
	
func set_left_join(left_join_obj: GDSQL.LeftJoin) -> GDSQL.BaseDao:
	__left_join = left_join_obj
	return self
	
func remove_left_join(left_join_obj: GDSQL.LeftJoin) -> bool:
	if __left_join == left_join_obj:
		__left_join = null
		return true
	return false
	
## 联表查询，简化用户输入参数，使用与主表相同的数据库和密码
func left_join_use_same_db_and_pass(table: String, alias: String, cond: String) -> GDSQL.BaseDao:
	return left_join(__db_name, table, alias, cond, _PASSWORD)
	
func left_join_use_user_db_and_default_pass(table: String, alias: String, cond: String) -> GDSQL.BaseDao:
	return left_join("user://", table, alias, cond, "")
	
## 联表查询，简化用户输入参数，使用游戏配置文件夹作为数据库，使用游戏配置文件的默认密码
func left_join_use_conf_db_and_default_pass(table: String, alias: String, cond: String) -> GDSQL.BaseDao:
	return left_join("res://src/config/", table, alias, cond, "")
	
## 获取联表查询的on条件（外部表格可能用到）。
func get_left_join_conds() -> Array:
	var ret = []
	if __left_join == null:
		return ret
	var arr_left_join = __left_join.get_chain_left_joins()
	for a_left_join in arr_left_join:
		var cond = a_left_join.get_condition()
		ret.push_back(cond)
	return ret
	
## 设置表达式中子查询
func set_sub_queries(p_sub_queries: Dictionary) -> GDSQL.BaseDao:
	__sub_queries.clear()
	for k in p_sub_queries:
		__sub_queries[k] = p_sub_queries[k]
	return self
	
## 设置额外表名
func set_input_names(p_input_names: Array) -> GDSQL.BaseDao:
	__input_names = p_input_names
	return self
	
## 设置额外表数据，和额外表明一一对应，比如[{'id': 1, 'sid': 1}, {'id': 1, 'eid': 1}]
func set_inputs(p_inputs: Array) -> GDSQL.BaseDao:
	__inputs = p_inputs
	return self
	
#func _collect_lack_table(info) -> bool:
	#if info is GDSQL.QueryResult:
		#if info.lack_data():
			#__lack_table.append_array(info.get_lack_tables())
			#return true
	#elif info is Dictionary:
		#var flag = false
		#for k in info:
			#flag = flag or _collect_lack_table(info[k])
		#return flag
	#return false
	
## 将复杂表达式转为简单表达式 
func _simplify_expression(expression: String, sql_input_names: Dictionary = {}, 
sql_static_inputs: Array = [], sql_varying_inputs: Dictionary = {}):
	var possible_sql = GDSQL.SQLParser.replace_nested_sql_expression(expression, 
		sql_input_names, sql_static_inputs, sql_varying_inputs, __request_password)
	if need_user_enter_password():
		return null
	var nested_sql_queries = {}
	if possible_sql is GDSQL.QueryResult:
		__sub_select_index += 1
		expression = "___Rep%d___" % __sub_select_index
		nested_sql_queries = {"sql": expression}
		nested_sql_queries[expression] = possible_sql
	elif possible_sql is Dictionary:
		expression = possible_sql.sql
		nested_sql_queries = possible_sql
		
	if not __sub_queries.is_empty():
		if not nested_sql_queries.is_empty():
			return _assert_false("___select", "Inner error 730 in base_dao.gd.")
			
		for k in __sub_queries:
			if nested_sql_queries.has(k):
				return _assert_false("___select", "Inner error 734 in base_dao.gd.")
			nested_sql_queries[k] = __sub_queries[k]
			
	return [expression, nested_sql_queries]
	
## 检查数组中的单个数据的结构是否都是一个键对应一个字典
func ___datas_struct_is_key_dict(datas: Array) -> bool:
	if datas.is_empty():
		return false
		
	# 检查第一个就行
	for k in datas[0]:
		if !(datas[0][k] is Dictionary):
			return false
	return true
	
func ___loop_table_row(result: Array, all_datas: Dictionary, loop_tables: Array, 
loop_index: int, curr_row: Dictionary, head: Array, table_definations: Dictionary) -> bool:
	if loop_index == loop_tables.size():
		# 最终满足所有条件，把数据塞到result中
		result.push_back(curr_row)
		#var ret = curr_row.duplicate() # 当前这条数据
		## 循环到头了，依次检查每个表是否满足on条件
		#var ok = true
		#var arr_left_join = __left_join.get_chain_left_joins()
		## 只要有一个条件不满足，这条数据就无效
		#for a_left_join in arr_left_join:
			#var cond = a_left_join.get_condition()
			#var conditionWrapper: GDSQL.ConditionWrapper = GDSQL.ConditionWrapper.new()
			#if not conditionWrapper.cond(cond).check(curr_row):
				#ok = false
				#break
				#
		#if ok:
			#result.push_back(ret)
			
	else:
		var table = loop_tables[loop_index]
		var need_fill_this_table_all_col_as_null = true
		if all_datas[table].size() > 0:
			# {
			#     'x': {
			#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
			#         false: index,		# false表示x是一个补充表名（来自__input_names）
			#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
			#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
			#     }
			# }
			var input_names = {} # input names based on curr_row TODO 缓存一下可以
			for t in curr_row:
				if not input_names.has(t):
					input_names[t] = {}
				input_names[t][true] = []
				for k in curr_row[t]:
					if not input_names.has(k):
						input_names[k] = {}
					input_names[k][t] = 0
					input_names[t][true].push_back(k)
					
			if not input_names.has(table):
				input_names[table] = {}
			input_names[table][true] = []
			for f in table_definations[table]:
				var col_name = f["Column Name"]
				if not input_names.has(col_name):
					input_names[col_name] = {}
				input_names[col_name][table] = 0
				input_names[table][true].push_back(col_name)
				
			for i in __input_names.size():
				var t = __input_names[i]
				if not input_names.has(t):
					input_names[t] = {}
				input_names[t][false] = i
				for k in __inputs[i]: # `__inputs[i]` is a Dictionary represent one row data
					if not input_names.has(k):
						input_names[k] = {}
					input_names[k][i] = 0
					
			for row in all_datas[table]:
				var acc_row = curr_row.duplicate()
				acc_row[table] = row
				
				# 实际上，虽然数据不全，但联表条件涉及的表必然已经在acc_row里了（如果用户
				# 的表达式是正确的话），所以已经可以检查是否满足阶段性的on条件了
				var lj = __left_join.get_left_join_by_alias(table)
				var cond = lj.get_condition()
				var simple_expression = _simplify_expression(cond, input_names, __inputs, acc_row)
				if need_user_enter_password():
					return false
				# 如果子查询依赖未知表的数据
				if not __lack_table.is_empty():
					if __collect_lack_table_enabled:
						return false # error occur or lacking table
					_assert_false("check left join on", "Unknown table(s): %s" % ", ".join(__lack_table))
					return false
				var condition_wrapper: GDSQL.ConditionWrapper = GDSQL.ConditionWrapper.new()
				var check_result = condition_wrapper.cond(simple_expression[0], 
					input_names, simple_expression[1]).check(__inputs, acc_row)
				if not condition_wrapper.get_lacking_tables().is_empty():
					if __collect_lack_table_enabled:
						__lack_table.append_array(condition_wrapper.get_lacking_tables())
						return false
					_assert_false("check left join on", "Unknown table(s): %s" % ", ".join(
						condition_wrapper.get_lacking_tables()))
					return false
				if typeof(check_result) != TYPE_BOOL:
					_assert_false("check left join on", "check failed! cond:%s" % cond)
					return false # error occur or lacking table
				if not check_result:
					continue
					
				need_fill_this_table_all_col_as_null = false
				if not ___loop_table_row(result, all_datas, loop_tables, 
				loop_index + 1, acc_row, head, table_definations):
					return false # error occur or lacking table
					
		# 当前表没有数据依旧要保持循环继续
		if need_fill_this_table_all_col_as_null:
			# 填充当前表的全null数据
			var acc_row = curr_row.duplicate()
			var a_row = {}
			for i in table_definations[table]:
				a_row[i["Column Name"]] = null
			acc_row[table] = a_row
			
			if not ___loop_table_row(result, all_datas, loop_tables, 
			loop_index + 1, acc_row, head, table_definations):
				return false # error occur or lacking table
	return true
	
func check_circular_dependency(dependencies: Dictionary):
	var visited = {} # visited字典用来跟踪哪些节点已经被访问过
	var rec_stack = {} # rec_stack字典用来记录递归调用栈中的节点
	# 遍历所有节点，检查每个节点是否存在循环依赖
	for node in dependencies.keys():
		# 如果节点未被访问，则检查该节点是否是循环依赖的一部分
		if not visited.has(node):
			if is_circular_util(node, dependencies, visited, rec_stack):
				return true
	# 如果所有节点都被检查过且没有发现循环依赖，则返回false
	return false
	
func is_circular_util(node, dependencies, visited, rec_stack):
	# 标记当前节点为已访问
	visited[node] = true
	rec_stack[node] = true
	# 如果当前节点有依赖的节点，遍历这些依赖节点
	if dependencies.has(node):
		for neighbour in dependencies[node]:
			# 如果依赖节点未被访问，则递归检查该依赖节点
			if not visited.has(neighbour):
				if is_circular_util(neighbour, dependencies, visited, rec_stack):
					return true
			# 如果依赖节点已经在递归栈中，说明存在循环依赖
			elif rec_stack.has(neighbour):
				return true
	# 当前节点检查完毕，从递归栈中移除
	rec_stack.erase(node)
	return false
	
func _get_init_datas(db_name: String, table_name: String, table_alias: String, password, fill_primary_key: String,
cond: String, all_table_defination: Dictionary, all_datas: Dictionary, curr_dependency: Dictionary = {}):
	if all_datas.has(table_alias):
		return
		
	var indexed_names = all_table_defination[table_alias].filter(func(v): return v.Index).map(func(v):
		return v["Column Name"]
	)
	var conf: GDSQL.ImprovedConfigFile = _get_conf(db_name, table_name, password, indexed_names) # 使用索引
	if conf == null:
		return _assert_false("___select", "failed to get conf: %s.%s" % [db_name, table_name])
	conf.fill_primary_key = fill_primary_key
	
	# 为了优化联表导致笛卡尔乘积带来的低效，先获取一下where条件，根据where条件提前筛一批数据
	if cond != '':
		# 查找和主键或索引有关的操作
		var col_names = []
		var pk_name = ""
		var indexed_name = []
		for i in all_table_defination[table_alias]:
			if i.PK:
				pk_name = i["Column Name"]
			if i.PK or i.Index:
				indexed_name.push_back(i["Column Name"])
			col_names.push_back(i["Column Name"])
			
		# 检查cond中是否涉及子查询
		var simple_expression = _simplify_expression(cond, __final_input_names, __inputs, {})
		if need_user_enter_password():
			return
		# 子查询依赖未知表的数据，暂时无法query出实际值，那么也不需要下面筛选表达式中涉及主键或
		# 索引的数据了，所以直接给全量数据。
		# 那么这影响left join吗，毕竟大部分on条件cond都涉及至少2个表？应该不影响，因为
		# __lack_table是指子查询缺失的表，而不是表达式缺失的表，所以不影响t.id == s.sid
		# 这类的一般表达式，因为它不携带子查询。
		if not __lack_table.is_empty():
			all_datas[table_alias] = conf.get_all_section_values()
			__lack_table.clear()
			return
			
		var expression = lru_cache.get_value([simple_expression, __final_input_names, __inputs])
		if expression == null:
			expression = GDSQL.SQLExpression.new()
			expression.sql_mode = true
			expression.set_sql_input_names(__final_input_names)
			expression.set_nested_sql_queries(simple_expression[1])
			expression.parse(simple_expression[0], [], __inputs)
			lru_cache.put_value([simple_expression, __final_input_names, __inputs], expression)
			
		# 主键或索引有关的操作， 例如一下cond：
		# "id == 1"
		# "1 == id"
		# "id in [1, 2, 3]"
		# "id in {'id': 1, 'name': 9}"
		# "t.id == 22 and 33 == id"
		# "id != 1 and id == 1"
		# "not id == 1"
		# "1 == 1 and not id == 1"
		# 分别返回：
		# { "==": 1 }
		# { "r==": 1 }
		# { "in": [1, 2, 3] }
		# { "in": { "id": 1, "name": 9 } }
		# { "and": { "left": { "==": 22 }, "right": { "r==": 33 } } }
		# { "and": { "left": { "!=": 1 }, "right": { "==": 1 } } }
		# { "not": { "left": { "==": 1 } } }
		# { "and": { "left": {  }, "right": { "not": { "left": { "==": 1 } } } } }
		var const_collection = []
		for a_name in indexed_name:
			var operations = {}
			expression.search_input_name_equal(expression.root, table_alias, a_name, operations)
			# 简化数据，收集可能的主键值或索引值
			# 常数的值比如1，2，3
			var a_collection = []
			var continu = _filter_pk_value(operations, a_collection, true)
			if not continu:
				const_collection.clear()
				break
				
			# 联表的主键值
			if table_alias != __table_alias: # 联表才查这个，主表不查
				var join_collection = []
				continu = _filter_pk_value(operations, join_collection, false)
				# false表示遇到不筛选的情况了
				if not continu:
					a_collection.clear()
					const_collection.clear()
					
				if not join_collection.is_empty():
					# 请求哪些表的数据，并检查在请求数据前的循环依赖状态
					var request = []
					for info in join_collection:
						# {
						#    "base": "", # table alias
						#    "name": "", # column name
						#    "index": "", # (base或name).在input_names的位置
						# }
						if not request.has(info.base):
							request.push_back(info.base)
					curr_dependency[table_alias] = request
					# 已经存在循环依赖了，那么这个表只能取全部数据了，就把const_collection清空，例如
					# {
					#     "A": ["B"] # A依赖B
					#     "B": ["C"] # B依赖C
					#     "C": ["A"] # C依赖A
					# }
					if check_circular_dependency(curr_dependency):
						const_collection.clear()
					else:
						for t in request:
							if not all_datas.has(t):
								var arr_left_join = __left_join.get_chain_left_joins() if __left_join != null else []
								for a_left_join in arr_left_join:
									if a_left_join.get_alias() == t:
										var db = a_left_join.get_db()
										var tb = a_left_join.get_table()
										var ps = a_left_join.get_password()
										var cd = a_left_join.get_condition()
										_get_init_datas(db, tb, t, ps, fill_primary_key, cd, 
											all_table_defination, all_datas, curr_dependency)
										break
							if not all_datas.has(t):
								for info in join_collection:
									if info.base == t:
										return _assert_false("___select", "Unknown column '%s.%s'." % 
											[info.base, info.name])
						# 把依赖的主键值加入const_collection
						for info in join_collection:
							for data in all_datas[info.base]:
								a_collection.push_back(data[info.name])
					# 清除依赖
					curr_dependency.erase(table_alias)
					
			if a_name == pk_name:
				const_collection.append_array(a_collection)
			else:
				for indexed_value in a_collection:
					const_collection.append_array(conf.get_sections_by_indexed_key(a_name, indexed_value))
					
		if not const_collection.is_empty():
			all_datas[table_alias] = []
			if const_collection.size() == 1:
				if conf.has_section(str(const_collection[0])):
					all_datas[table_alias].push_back(conf.get_section_values(str(const_collection[0]), col_names))
			else:
				var uniq_collection = []
				for i in const_collection:
					if not str(i) in uniq_collection:
						uniq_collection.push_back(str(i))
				uniq_collection.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
				if not uniq_collection.is_empty():
					for pk_value in uniq_collection:
						if conf.has_section(pk_value):
							all_datas[table_alias].push_back(conf.get_section_values(pk_value, col_names))
							
	# 主表没数据时，取主表所有数据
	if not all_datas.has(table_alias):
		all_datas[table_alias] = conf.get_all_section_values()
		
func ___select(fill_primary_key: String = ""):
	# 需要重置的属性：
	__sub_select_index = -1
	__select_query_columns_count = 0
	#__simplify_exp_cache.clear()
	__lack_table.clear()
	__err.clear()
	
	var ret: Array = []
	# 表结构定义
	var all_table_defination = {}
	all_table_defination[__table_alias] = __get_table_defination(__db_name, __table)["columns"]
	var arr_left_join = __left_join.get_chain_left_joins() if __left_join != null else []
	for a_left_join: GDSQL.LeftJoin in arr_left_join:
		if not a_left_join.validate():
			__err.append_array(a_left_join.get_err())
			return null
	for a_left_join: GDSQL.LeftJoin in arr_left_join:
		var err = a_left_join.handle_defualt_password()
		if err != OK:
			__err.append_array(a_left_join.get_err())
			return null
		if a_left_join.need_user_enter_password():
			__request_password.push_back(true)
			return null
		all_table_defination[a_left_join.get_alias()] = __get_table_defination(
			a_left_join.get_db(), a_left_join.get_table())["columns"]
	var all_datas: Dictionary = {} # 把所有表的数据放到这个里边
	
	# 收集每个表名以及每个字段
	# {
	#     'x': {
	#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
	#         false: index,		# false表示x是一个补充表名（来自__input_names）
	#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
	#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
	#     }
	# }
	__final_input_names.clear()
	for t in all_table_defination:
		if not __final_input_names.has(t):
			__final_input_names[t] = {}
		__final_input_names[t][true] = [] # true: ['a', 'b']
		for f in all_table_defination[t]:
			var col_name = f["Column Name"]
			if not __final_input_names.has(col_name):
				__final_input_names[col_name] = {}
			__final_input_names[col_name][t] = 0 # 'y': 0
			__final_input_names[t][true].push_back(col_name)
			
	for i in __input_names.size():
		var t = __input_names[i]
		if not __final_input_names.has(t):
			__final_input_names[t] = {}
		__final_input_names[t][false] = i # false: 0
		for k in __inputs[i]: # `__inputs[i]` is a Dictionary represent one row data
			if not __final_input_names.has(k):
				__final_input_names[k] = {}
			__final_input_names[k][i] = 0 # N: 0
			
	# 为了优化联表导致笛卡尔乘积带来的低效，先获取一下where条件，根据where条件提前筛一批数据
	var cond = _get_cond(false)
	# 主表数据
	_get_init_datas(__db_name, __table, __table_alias, _PASSWORD, fill_primary_key, cond, 
		all_table_defination, all_datas)
		
	# 取联表所有数据
	for a_left_join in arr_left_join:
		var db = a_left_join.get_db()
		var tb = a_left_join.get_table()
		var al = a_left_join.get_alias()
		var ps = a_left_join.get_password()
		var cd = a_left_join.get_condition()
		_get_init_datas(db, tb, al, ps, fill_primary_key, cd, all_table_defination, all_datas)
		
	# 计算表头
	var real_select = __get_head(all_datas, arr_left_join)
	if real_select == null:
		return _assert_false("___select", "failed to get ResultSet's head.")
		
	# QueryResulty用
	__select_query_columns_count = real_select.size()
	
	# 检查一下是否有order_by所要的数据
	for a_order_by in __order_by:
		if a_order_by[0] is int:
			if a_order_by[0] > real_select.size() or a_order_by[0] <= 0:
				return _assert_false("___select", "Unknown column '%s' in 'order clause'" % a_order_by[0])
		else:
			var find = false
			for i in real_select:
				if i.select_name == a_order_by[0] or i.field_as == a_order_by[0] or \
				((i.table_alias + "." + i.select_name) == a_order_by[0]):
					find = true
					break
			if not find:
				return _assert_false("___select", "Unknown column '%s' in 'order clause'" % a_order_by[0])
				
	# 不联表的情况
	if __left_join == null:
		# 统一转化成按表名分类的结构
		for data in all_datas[__table_alias]:
			ret.push_back({__table_alias: data})
	# 联表的情况筛选符合on条件的数据
	else:
		# 有几张表，就要做几重循环
		var loop_tables: Array = all_datas.keys()
		loop_tables.erase(__table_alias)
		for row in all_datas[__table_alias]:
			var row_result = []
			var acc_row = {__table_alias: row}
			
			# 把额外补充的信息加入acc_row，因为可能在计算的时候需要这些数据。
			# 如果额外表的名字和主表或leftjoin的表名一致，就忽略额外补充的数据。
			var t_index = -1
			for t in __input_names:
				t_index += 1
				if t == __table_alias:
					continue
				var flag = false
				for a_left_join in arr_left_join:
					if t == a_left_join.get_alias():
						flag = true
						break
				if flag:
					continue
				acc_row[t] = __inputs[t_index]
				
			if not ___loop_table_row(row_result, all_datas, loop_tables, 0, 
			acc_row, real_select, all_table_defination):
				return null # error occur or lacking table
				
			# NOTICE row_result可能包含__input_names表和__inputs数据
			if row_result.is_empty():
				var one_row = {__table_alias: row}
				for a_left_join in arr_left_join:
					var a_row = {}
					var a_alias = a_left_join.get_alias()
					for i in all_table_defination[a_alias]:
						a_row[i["Column Name"]] = null
					one_row[a_left_join.get_alias()] = a_row
				ret.push_back(one_row)
			else:
				ret.append_array(row_result)
				
	## 空数据并且不需要返回表头
	#if ret.is_empty() and (__parent_union != null or not __need_head):
		#return ret
		#
	## 空数据要表头
	#if ret.is_empty():
		#return [real_select]
		
	var ret_filter = null
	if cond == "" or ret.is_empty():
		ret_filter = ret
	else:
		# data先传空字典，看看能否让ret中的每一行都共用同一个expression
		var simple_expression = _simplify_expression(cond, __final_input_names, __inputs, {})
		if need_user_enter_password():
			return null
		# 如果有子查询依赖未知表的情况
		if not __lack_table.is_empty():
			# NOTICE 这里还不能在__collect_lack_table_enabled为true时进行返回，因为
			# 依赖的表可能是存在的，需要在传入每一行数据时调用_simplify_expression后再
			# 决定是否需要直接返回。
			#if __collect_lack_table_enabled:
				#return null
			#else:
			# 缺数据，那么simple_expression就不能共享同一个expression了，
			# 而是需要每一行data单独一个expression
			simple_expression = null
			__lack_table.clear()
			
		ret_filter = []
		var condition_wrapper: GDSQL.ConditionWrapper = GDSQL.ConditionWrapper.new()
		if simple_expression:
			condition_wrapper.cond(simple_expression[0], __final_input_names, simple_expression[1])
		# NOTICE data可能已经包含了__input_names表和__inputs数据
		for data in ret:
			var a_expression = simple_expression
			# 不共享simple_expression的情况
			if a_expression == null:
				a_expression = _simplify_expression(cond, __final_input_names, __inputs, data)
				if need_user_enter_password():
					return null
				if not __lack_table.is_empty():
					if __collect_lack_table_enabled:
						return null
					return _assert_false("computing field", "Unknown table(s): %s" % ", ".join(__lack_table))
				condition_wrapper.cond(simple_expression[0], __final_input_names, simple_expression[1])
				
			var check_result = condition_wrapper.check(__inputs, data)
			if not condition_wrapper.get_lacking_tables().is_empty():
				if __collect_lack_table_enabled:
					__lack_table.append_array(condition_wrapper.get_lacking_tables())
					return null
			if typeof(check_result) != TYPE_BOOL:
				return _assert_false("check where", "check failed! cond:%s" % cond)
			if check_result:
				ret_filter.push_back(data)
				
	# 不用后处理，那么就返回所有字段，这基本就是update的时候内部调用select才使用。用户不应该到这里。所以不加表头了。
	if not __need_post_porcess:
		return ret_filter
		
	# group by 预分组，让每行每列对应某个聚合对象
	GDSQL.AggregateFunctions.clear_instances()
	var pre_group_can_remain = {} # 第几行数据（不包括表头） => 可以保留
	var pre_group = {} # 第几行数据 => {col => agg_func_obj}
	var pre_group_last_row = {} # map => 最后一行数据的序号。为了找到每个聚合的最后一条数据
	var last_group_row_index = {}
	var total_agg_func_obj = {} # col => agg_func_obj。在没有group by但是用了聚合函数的时候有用
	if __group_by.is_empty():
		for i in real_select.size():
			if GDSQL.AggregateFunctions.possible_has_func(real_select[i].select_name):
				total_agg_func_obj[i] = GDSQL.AggregateFunctions.get_instance(i)
		#for i in __order_by.size():
			#if GDSQL.AggregateFunctions.possible_has_func(__order_by[i][0]):
				#var index = real_select.size() + i
				#total_agg_func_obj[index] = GDSQL.AggregateFunctions.get_instance(index)
	else:
		var group_key = []
		# NOTICE group by的key不支持子查询，这在group_by函数中进行了约束
		for i: String in __group_by:
			var find = false
			for j in real_select:
				if (j.select_name == i or j.field_as == i) and j.is_field:
					find = true
					group_key.push_back([j.table_alias, j["Column Name"]])
					break
			if not find:
				if i.is_valid_int():
					if int(i) >= 1 and int(i) <= real_select.size():
						find = true
						group_key.push_back([real_select[int(i)-1].table_alias, real_select[int(i)-1]["Column Name"]])
						continue
					else:
						return _assert_false("in group statement", "Unknow column '%s' in 'group statement'" % i)
				group_key.push_back(i)
				
		var grouped_map = {}
		var data_index = -1
		for data in ret_filter:
			data_index += 1
			var grouped_value = []
			for j in group_key:
				if j is Array:
					grouped_value.push_back(data[j[0]][j[1]])
				else: # j is String
					var m_data = ret_filter[data_index] # map形式的data
					var value = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
						null, j, [], [], __final_input_names, __inputs, m_data,
						__sub_queries, __lack_table)
					if not __lack_table.is_empty():
						if __collect_lack_table_enabled:
							return null
						return _assert_false("computing group value", "Unknown table(s): %s" % ", ".join(__lack_table))
					grouped_value.push_back(value)
					
			var map = grouped_map
			var find = false
			for i in grouped_value:
				if map.has(i):
					find = true
					map = map.get(i)
				else:
					find = false
					break
			if find:
				pre_group[data_index] = map
			else:
				pre_group_can_remain[data_index] = true
				map = grouped_map
				for i in grouped_value:
					if not map.has(i):
						map[i] = {}
					map = map[i]
				for i in real_select.size():
					if GDSQL.AggregateFunctions.possible_has_func(real_select[i].select_name):
						map[i] = GDSQL.AggregateFunctions.get_instance(str(data_index) + "#" + str(i))
				for i in __order_by.size():
					if GDSQL.AggregateFunctions.possible_has_func(__order_by[i][0]):
						var index = real_select.size() + i
						map[index] = GDSQL.AggregateFunctions.get_instance(str(data_index) + "#" + str(index))
				pre_group[data_index] = map
			pre_group_last_row[map] = data_index
			
	# 找到了某一行数据是最后一个聚合函数作用的数据了
	for i in pre_group_last_row:
		last_group_row_index[pre_group_last_row[i]] = true
	pre_group_last_row.clear() # 没用了
	
	var ret_post_process: Array = []
	# 表头
	var head = real_select
	var has_head = false
	if __need_head and __parent_union == null:
		has_head = true
		ret_post_process.push_back(head)
		
	# order by 对应的列的序号
	var for_order = [] 
	for i in __order_by.size():
		var col_index
		if __order_by[i][0] is int:
			col_index = __order_by[i][0] - 1
		else:
			var a_index = -1
			for j in real_select:
				a_index += 1
				if j.select_name == __order_by[i][0] or j.field_as == __order_by[i][0] or \
				((j.table_alias + "." + j.select_name) == __order_by[i][0]):
					col_index = a_index
					break
					
		for_order.push_back(col_index)
		
	# 确认的使用了聚合对象来完成计算的结果
	var agg_func_obj_final_col_value = {} # obj => value
	var confirmed_value_with_agg_func = {} # 第row行数据 => {第col个数 => 计算结果}
	# 下面按照用户需要的字段及其顺序，返回相应的数据
	# 为了提升效率，简化一些常用查询。单表查询并查全字段
	if __left_join == null and __select.size() == 1 and \
	(__select[0] == "*" or __select[0] == __table_alias + ".*"):
		for d in ret_filter:
			var row = []
			for f in real_select:
				if d[__table_alias].has(f["Column Name"]):
					row.push_back(d[__table_alias][f["Column Name"]])
				else:
					row.push_back(null)
			for i in for_order:
				row.push_back(row[i])
			ret_post_process.push_back(row)
	else:
		## 数据格式是统一按表分类的，把字段中点号取值处理成方括号取值
		## 匹配t.name.substr(10)这种字符串。不匹配的会原样输出，不会被替换
		## 注意：这里不兼容t.name.a.b.substr(10)这种太多级的写法。会被改成t["name"].a["b"].substr(10)
		## UPDATE：上面3行注释说的内容是不需要的，因为Dictionary实际是支持点号的，不用转成方括号。
		#for f in real_select.size():
			## t.name.substr(10) 被替换为：t["name"].substr(10)
			#if real_select[i]["is_field"] or real_select[i]["select_name"].contains("."):
				#real_select[i]["name_4_computing"] = real_select[i]["select_name"]
			#else:
				#real_select[i]["name_4_computing"] = GDSQL.ConditionWrapper.modify_dot_to_get(real_select[i]["select_name"])
		# 求值
		var data_index = -1
		for data in ret_filter:
			data_index += 1
			# 每行就是一个数组，按照用户select的顺序排列的，用户自己取。原来的想法是row是一个字典，
			# 但是存在一个值是由多个表里的数据或者并不是某个表里的数据计算出来的，不太好处理，放弃了。
			# 另外存在一个问题，就是星号怎么办。一个星号就代表了这个表所有的字段，用户很难知道返回的数据每个元素都对应哪个字段
			# 所以考虑返回数据的第一行是一个表头（用户可以传参数要不要这个表头）。
			# （这个考虑的结果最终决定了在上面的代码中增加了表头处理）
			var row = []
			# 按字段顺序挨个处理
			var index = -1
			for field in real_select:
				index += 1
				# 如果field不是一个字段，比如是一个单纯的数字、字符串，在union的时候，会有问题，后续表会用首表的字段
				# 考虑union的时候，开启__need_post_porcess，并把最终结果放到某个特定的字段下，且仍旧返回按表分类的数据结构
				# 求值的时候增加一个判断分支，如果数据存在这个特定的字段，则不进行求值，而是直接使用已经求出的值
				# 直到第一个BaseDao，会返回扁平结构的数据
				var dealed = false
				if field.is_field and data.has(field.table_alias):
					if data[field.table_alias].has(field.name_4_computing):
						row.push_back(data[field.table_alias][field.name_4_computing])
						dealed = true
					#elif field.name_4_computing == field.table_alias + "." + field["Column Name"]:
					elif field.name_4_computing.get_slice_count(".") == 2 and \
					field.name_4_computing.get_slice(".", 0).strip_edges() == field.table_alias and \
					field.name_4_computing.get_slice(".", 1).strip_edges() == field["Column Name"]:
						row.push_back(data[field.table_alias][field["Column Name"]])
						dealed = true
				if not dealed:
					# 聚合函数对象
					var agg_func_obj = null
					# 未使用group by但是使用了聚合函数时，在最后一行数据的时候设置聚合对象的状态为准备就绪
					if total_agg_func_obj.has(index):
						agg_func_obj = total_agg_func_obj.get(index) as GDSQL.AggregateFunctions
						if data_index == ret_filter.size() - 1:
							GDSQL.AggregateFunctions.prepare_done(agg_func_obj.id)
					elif pre_group.has(data_index) and pre_group[data_index].has(index):
						agg_func_obj = pre_group[data_index][index] as GDSQL.AggregateFunctions
						if last_group_row_index.has(data_index):
							GDSQL.AggregateFunctions.prepare_done(agg_func_obj.id)
					if agg_func_obj:
						GDSQL.AggregateFunctions.recount(agg_func_obj.id) # 每条数据前需要recount
						
					var simple_expression = _simplify_expression(
						field.name_4_computing, __final_input_names, __inputs, data)
					if need_user_enter_password():
						return null
					# 如果有子查询依赖未知表的情况
					if not __lack_table.is_empty():
						if __collect_lack_table_enabled:
							return null
						return _assert_false("computing field", "Unknown table(s): %s" % ", ".join(__lack_table))
					var value = GDSQL.GDSQLUtils.evalute_command_with_agg(agg_func_obj, 
						simple_expression[0], [], [], __final_input_names, __inputs, data, simple_expression[1])
					if value is GDSQL.QueryResult:
						var rows = value.get_data()
						if rows.is_empty():
							value = null
						elif rows.size() > 1:
							return _assert_false("in sub query", 
								"Subquery [%s] returns more than 1 row." % field.name_4_computing)
						elif rows[0].size() > 1:
							return _assert_false("in sub query", 
								"Subquery [%s] returns more than 1 column." % field.name_4_computing)
						else:
							value = rows[0][0]
					row.push_back(value)
					
					# 记录该列聚合结果。_used为true表示真的被使用了。
					if agg_func_obj and agg_func_obj._used and not agg_func_obj._preparing:
						if not confirmed_value_with_agg_func.has(data_index):
							confirmed_value_with_agg_func[data_index] = {}
						confirmed_value_with_agg_func[data_index][index] = value
						if not agg_func_obj_final_col_value.has(agg_func_obj):
							agg_func_obj_final_col_value[agg_func_obj] = {}
						agg_func_obj_final_col_value[agg_func_obj][index] = value
						
			# 把order by要用的value也装进来
			var a_index = real_select.size() - 1
			for i in for_order:
				a_index += 1
				row.push_back(row[i])
				
				# 关联一下这列的最终值
				if confirmed_value_with_agg_func.has(data_index) and \
				confirmed_value_with_agg_func[data_index].has(i):
					confirmed_value_with_agg_func[data_index][a_index] = \
						confirmed_value_with_agg_func[data_index][i]
						
			ret_post_process.push_back(row)
			
	# group by 分组，支持列别名
	var grouped_ret = null
	if __group_by.is_empty():
		# 100%没使用聚合函数
		if total_agg_func_obj.is_empty():
			grouped_ret = ret_post_process
		# 疑似使用了聚合函数。如果真用了，要把结果集改为单独的一条聚合结果。如果没用，需要保留原始数据
		else:
			# 聚合结果字典不为空，那100%用了聚合函数
			if not confirmed_value_with_agg_func.is_empty():
				# 就一个key，弄出来
				for row_index in confirmed_value_with_agg_func:
					confirmed_value_with_agg_func = confirmed_value_with_agg_func[row_index]
					break
				var row = []
				var first_row
				if has_head:
					first_row = ret_post_process[1]
				else:
					first_row = ret_post_process[0]
				for i in real_select.size() + __order_by.size():
					if first_row.size() > i:
						if confirmed_value_with_agg_func.has(i):
							row.push_back(confirmed_value_with_agg_func[i])
						else:
							row.push_back(first_row[i])
							
				# 原数据有head的时候记得加上
				if has_head:
					grouped_ret = [ret_post_process[0], row]
				else:
					grouped_ret = [row]
			# 聚合结果字典为空，而且数据集不为空，那说明没有使用真实聚合函数，不做处理
			elif (has_head and ret_post_process.size() > 1) or (not has_head and ret_post_process.size() > 0):
				grouped_ret = ret_post_process
			# 数据集为空，还是要继续检查，因为数据集为空不能说明是否用了聚合函数
			else:
				# 检查一下确实是空数据集
				if not ((has_head and ret_post_process.size() == 1) or ret_post_process.is_empty()):
					assert(false, "Inner error 501.") # 有没考虑到的情况？
					return null
				# 构造一条数据，看是否使用了聚合函数对象
				var has_real_agg_func = false
				# 把求式子可能需要的变量名称和变量值都放到数组里
				var data = {} # 全null的数据
				for key: String in all_table_defination:
					data[key] = {}
					for f in all_table_defination[key]:
						data[key][f["Column Name"]] = null
						
				# 一条新数据，即聚合结果
				var row = []
				for i in real_select.size():
					var agg_func_obj = null
					if total_agg_func_obj.has(i):
						agg_func_obj = total_agg_func_obj[i] as GDSQL.AggregateFunctions
						GDSQL.AggregateFunctions.enable_empty_data_mode(agg_func_obj.id)
						GDSQL.AggregateFunctions.prepare_done(agg_func_obj.id)
						var simple_expression = _simplify_expression(
							real_select[i].name_4_computing, __final_input_names, __inputs, data)
						if need_user_enter_password():
							return null
						# 如果有子查询依赖未知表的情况
						if not __lack_table.is_empty():
							if __collect_lack_table_enabled:
								return null
							return _assert_false("computing field", "Unknown table(s): %s" % ", ".join(__lack_table))
						var value = GDSQL.GDSQLUtils.evalute_command_with_agg(agg_func_obj, 
							simple_expression[0], [], [], __final_input_names, __inputs, data, simple_expression[1])
						# 如果只使用ifnull或ifn，是不算的，不能额外返回一条聚合数据
						if agg_func_obj._used and agg_func_obj._is_real_aggregate_func:
							has_real_agg_func = true
						# 没使用聚合函数，那结果应该是null
						else:
							value = null
						row.push_back(value)
					else:
						row.push_back(null)
						
				# 把order by要用的value也装进来
				for i in __order_by.size():
					var col_index
					if __order_by[i][0] is int:
						col_index = __order_by[i][0] - 1
					else:
						var a_index = -1
						for j in real_select:
							a_index += 1
							if j.select_name == __order_by[i][0] or j.field_as == __order_by[i][0]:
								col_index = a_index
								break
								
					var value = row[col_index]
					row.push_back(value)
					
				# 确实用了聚合函数
				if has_real_agg_func:
					# 原数据有head的时候记得加上
					if has_head:
						grouped_ret = [ret_post_process[0], row]
					else:
						grouped_ret = [row]
				# 没用，那么保留原数据
				else:
					grouped_ret = ret_post_process
	else:
		grouped_ret = []
		var data_index = -1
		var head_offset = 0
		for data in ret_post_process:
			data_index += 1
			if has_head and data_index == 0:
				grouped_ret.push_back(data)
				head_offset = -1
				continue
				
			var real_index = data_index + head_offset
			if pre_group_can_remain.has(real_index):
				# 聚合函数的结果覆盖掉第一条数据
				for i in data.size():
					if pre_group.has(real_index) and pre_group[real_index].has(i) and \
					pre_group[real_index][i]._used:
						data[i] = agg_func_obj_final_col_value[pre_group[real_index][i]][i]
				grouped_ret.push_back(data)
				
	GDSQL.AggregateFunctions.clear_instances()
	
	# order by, limit 都需要在主BaseDao上执行，所以非主BaseDao的就可以直接返回了
	if __parent_union:
		return grouped_ret
		
	# 合并union
	if __union_all:
#		__union_all.__need_post_porcess = false # 改为需要后处理
#		__union_all.__need_head = false
		# 为了让union表数据包含order by的列，需要先设置一下
		__union_all.__order_by = __order_by.duplicate()
		var err = __union_all._handle_defualt_password()
		if err != OK:
			return null
		if __union_all.need_user_enter_password():
			__request_password.push_back(true)
			return null
			
		var union_datas = __union_all.___select()
		if __union_all.need_user_enter_password():
			return null
		if union_datas == null:
			if __collect_lack_table_enabled and not __union_all.__lack_table.is_empty():
				__lack_table.append_array(__union_all.get_lack_table())
				__union_all.reset()
				return null
			__union_all.reset()
			return _assert_false("___select", "Error occur!")
		grouped_ret.append_array(union_datas)
		# 防止内存占用
		__union_all.reset()
		
	# 如果是空数据
	if grouped_ret.is_empty() or (has_head and grouped_ret.size() == 1):
		return grouped_ret
		
	# 排序，支持列别名
	if not __order_by.is_empty() and not grouped_ret.is_empty() and (
		(has_head and grouped_ret.size() > 2) or \
		(not has_head and grouped_ret.size() > 1)):
		var compare := func(a, b):
			if is_same(a, head):
				return true
			if is_same(b, head):
				return false
			var index = -1
			for a_order_by in __order_by:
				index += 1
				var order_value_index = real_select.size() + index
				var v1 = a[order_value_index]
				var v2 = b[order_value_index]
				if v1 == v2:
					continue
				else:
					if a_order_by[1] == GDSQL.ORDER_BY.ASC:
						if v1 == null and v2 != null:
							return true
						if v2 == null and v1 != null:
							return false
						if v1 == null and v2 == null:
							return false
						if v1 < v2:
							return true
						return false
					else:
						if v1 == null and v2 != null:
							return false
						if v2 == null and v1 != null:
							return true
						if v1 == null and v2 == null:
							return false
						if v1 > v2:
							return true
						return false
			return false
			
		grouped_ret.sort_custom(compare)
		
	# limit
	if __offset >= 0 and __limit > 0:
		if __offset == 0:
			grouped_ret = grouped_ret.slice(__offset, __limit + int(has_head))
		elif has_head:
			grouped_ret = [head] + grouped_ret.slice(__offset + 1, __offset + __limit + 1)
		else:
			grouped_ret = grouped_ret.slice(__offset + int(has_head), __offset + __limit + int(has_head))
			
	# 去掉多余的_order_by的数据
	if not __order_by.is_empty():
		var remove_num = __order_by.size()
		for i in grouped_ret:
			if i is Array and i.size() > real_select.size():
				for j in remove_num:
					if i.size() > real_select.size():
						i.pop_back()
					else:
						break
	## 替换表头
	#grouped_ret[0] = real_select
	return grouped_ret
	
## 简化主表数据的逻辑是：
## 1. 包含not的，一律不做筛选；
## 2. 包含!=的，一律不做筛选；
## 3. 如果遇到null（属于复杂情况），一律不做筛选
## 4. 遇到==、r==，记录操作数
## 5. 遇到in，记录操作数（数组）或记录操作数的键（字典）
## constant_mode: 常数模式还是其他表字段模式
func _filter_pk_value(dict: Dictionary, collection: Array, constant_mode: bool):
	if dict.is_empty():
		return true
	if dict.has("not") or dict.has("!=") or dict.values().has(null):
		collection.clear()
		return false # false表示终止递归
	for op in ["==", "r=="]:
		if dict.has(op):
			var ret = [dict[op]]
			# 涉及运算的，（即便参与运算的都是常数）都不算常数
			if GDSQL.SQLExpression.is_none_const_expression_e_node(dict[op], ret):
				collection.clear()
				return false # 复杂情况，false终止递归
				
			dict[op] = ret[0]
			if constant_mode:
				# WARNING 这里因为我们判断的是主键值，所以一般是int或String
				if typeof(dict[op]) in PRIMARY_TYPES:
					collection.push_back(dict[op])
				elif typeof(dict[op]) in NORMAL_TYPES:
					pass # 这些类型的忽略，也不需要清空collection
				elif dict[op] is GDSQL.QueryResult:
					var rows = (dict[op] as GDSQL.QueryResult).get_data()
					if not rows.is_empty():
						if rows[0].size() != 1:
							collection.clear()
							return _assert_false("filter pk value", "Operand `%s` should contain 1 column." % op)
						if rows.size() != 1:
							collection.clear()
							return _assert_false("filter pk value", "Subquery returns more than 1 row.")
						if typeof(rows[0][0]) in PRIMARY_TYPES:
							collection.push_back(rows[0][0])
				# Object which is not ExpressionENode
				else:
					pass # 这种类型忽略，也不需要清空collection
			else:
				# NOTICE 这里判断的是主键值是否是另一个表的字段
				if dict[op] is Dictionary and dict[op].keys() == ["base", "name", "index"]:
					collection.push_back(dict[op])
				else:
					pass # 其他情况，都不需要清空collection。
					
			return true # 只可能包含一种操作符
	if dict.has("in"):
		var ret = [dict.in]
		if GDSQL.SQLExpression.is_none_const_expression_e_node(dict.in, ret):
			collection.clear()
			return false
			
		dict.in = ret[0]
		
		# 下面分情况讨论一些支持in操作的数据类型：String, Array, Dictionary, QueryResult
		
		# id in "abc"，那么id可选择的范围很多：a, b, c, ab, ac, bc, abc
		# 这样就比较复杂了。所以直接当作复杂情况。
		if dict.in is String:
			collection.clear()
			return false
		elif dict.in is Array:
			if constant_mode:
				collection.append_array(dict.in)
			else:
				pass # do nothing
		elif dict.in is Dictionary:
			if constant_mode:
				if not dict.in.keys() == ["base", "name", "index"]:
					collection.append_array(dict.in.keys())
			else:
				if dict.in.keys() == ["base", "name", "index"]:
					collection.push_back(dict.in)
		elif dict.in is GDSQL.QueryResult:
			if constant_mode:
				var rows = (dict.in as GDSQL.QueryResult).get_data()
				if not rows.is_empty():
					if rows[0].size() != 1:
						collection.clear()
						return _assert_false("filter pk value", "Operand `in` should contain 1 column.")
					for row in rows:
						collection.push_back(row[0])
			else:
				pass # do nothing
		return true
	for key in ["left", "right"]:
		if dict.has(key):
			var continu = _filter_pk_value(dict[key], collection, constant_mode)
			if not continu:
				return false
	for key in ["and", "or"]:
		if dict.has(key):
			var continu = _filter_pk_value(dict[key], collection, constant_mode)
			if not continu:
				return false
	return true
	
## 获取字段名称的正则
func _get_regex_field(table_alias: String) -> RegEx:
	if regex_field_map.has(table_alias):
		return regex_field_map[table_alias]
	var regex_field = RegEx.new()
	regex_field.compile(table_alias + "(\\s*)\\.(\\s*)([a-zA-Z_]+[0-9a-zA-Z_]*)")
	regex_field_map[table_alias] = regex_field
	return regex_field
	
func __get_head(all_datas: Dictionary, arr_left_join: Array):
	var real_select = []
	var gen_dict = func(s, c, f, t_alias = "", d = "", t = ""):
		return {"select_name": s, "Column Name": c, "is_field": f, "table_alias": t_alias,
			"db_path": d, "table_name": t, "hint": PROPERTY_HINT_NONE, "Hint String": ""}
	var fill_select_name = func(element, alias):
		element["select_name"] = element["Column Name"] if alias == "" \
			else (alias + "." + element["Column Name"])
		return element
		
	var asterisk_index_count = {} # *出现的位置和代表的字段数量
	var index = -1
	for s in __select:
		index += 1
		var pre_size = real_select.size()
		if s == "*":
			for alias in all_datas:
				if alias == __table_alias:
					real_select.append_array(
						__get_table_columns(__db_name, __table, __table_alias)
						.map(fill_select_name.bind(alias)))
				else:
					var a_left_join = __left_join.get_left_join_by_alias(alias)
					real_select.append_array(
						__get_table_columns(a_left_join.get_db(), a_left_join.get_table(), alias)
						.map(fill_select_name.bind(alias)))
			asterisk_index_count[index] = real_select.size() - pre_size
		elif s.ends_with(".*"):
			var alias = s.substr(0, s.length() - 2)
			if alias == __table_alias:
				real_select.append_array(
					__get_table_columns(__db_name, __table, __table_alias)
					.map(fill_select_name.bind(alias)))
			else:
				if __left_join == null:
					return _assert_false("___select", "table `%s` not found" % alias)
				var a_left_join = __left_join.get_left_join_by_alias(alias)
				if a_left_join == null:
					return _assert_false("___select", "table `%s` not found" % alias)
				real_select.append_array(
					__get_table_columns(a_left_join.get_db(), a_left_join.get_table(), alias)
						.map(fill_select_name.bind(alias)))
			asterisk_index_count[index] = real_select.size() - pre_size
		else:
			var m = regex_symbol.search(s)
			if m != null and m.get_string() == s:
				if __left_join != null:
					return _assert_false("___select", 
						"must specify table alias name in select fields if using left join")
				var column = __get_table_column_defination(__db_name, __table, __table_alias, m.get_string())
				if column != null and !column.is_empty():
					real_select.push_back(column)
				else:
					if all_datas[__table_alias].is_empty() or not all_datas[__table_alias][0].has(s):
						return _assert_false("___select",
							"field:[%s] not exist in table:[%s], db:[%s]" % [s, __table, __db_name])
					real_select.push_back(gen_dict.call(s, s, true, __table_alias)) # 可能没有定义文件
			#elif s.contains(__table_alias + "."):
			elif s.get_slice_count(".") == 2 and s.get_slice(".", 0).strip_edges() == __table_alias:
				m = _get_regex_field(__table_alias).search(s)
				if m:
					var field = m.get_string(3)
					var column = __get_table_column_defination(__db_name, __table, __table_alias, field)
					if column != null and !column.is_empty():
						if s == __table_alias + m.get_string(1) + "." + m.get_string(2) + field:
							column["select_name"] = s
							real_select.push_back(column)
						else:
							real_select.push_back(gen_dict.call(s, s, false))
					else:
						if s == __table_alias + m.get_string(1) + "." + m.get_string(2) + field:
							if all_datas[__table_alias].is_empty() or not all_datas[__table_alias][0].has(field):
								return _assert_false("___select",
									"field:[%s] not exist in table:[%s], db:[%s]" % [field, __table, __db_name])
							real_select.push_back(gen_dict.call(s, field, true, __table_alias, __db_path, __table))
						else:
							real_select.push_back(gen_dict.call(s, s, false))
				else:
					# 不能100%确定有错误，所以不报错了
					real_select.push_back(gen_dict.call(s, s, false))
			else:
				var find = false
				for a_left_join in arr_left_join:
					var alias = a_left_join.get_alias()
					#if s.contains(alias + "."):
					if s.get_slice_count(".") == 2 and s.get_slice(".", 0).strip_edges() == alias:
						find = true
						m = _get_regex_field(alias).search(s)
						if m:
							var field = m.get_string(3)
							var column = __get_table_column_defination(
								a_left_join.get_db(), a_left_join.get_table(), alias, field)
							if column != null and !column.is_empty():
								if s == alias + m.get_string(1) + "." + m.get_string(2) + field:
									column["select_name"] = s
									real_select.push_back(column)
								else:
									real_select.push_back(gen_dict.call(s, s, false))
							else:
								if s == alias + m.get_string(1) + "." + m.get_string(2) + field:
									if all_datas[alias].is_empty() or not all_datas[alias][0].has(field):
										return _assert_false("___select",
											"field:[%s] not exist in table:[%s], db:[%s]" \
											% [field, a_left_join.get_table(), a_left_join.get_db()])
									real_select.push_back(gen_dict.call(s, field, true, alias, 
										a_left_join.get_db(), a_left_join.get_table())) # 没定义的文件
								else:
									real_select.push_back(gen_dict.call(s, s, false))
						break
						
				if not find:
					real_select.push_back(gen_dict.call(s, s, false))
					
	var field_as_index = {}
	# field as 出现的位置
	for i in __field_as_index:
		var offset = 0
		# *出现的位置和代表的字段数量
		for j in asterisk_index_count:
			if j < i:
				if asterisk_index_count[j] > 0:
					offset += asterisk_index_count[j] - 1 # -1是因为星号是被替换掉了
			else:
				break
		field_as_index[i + offset] = __field_as_index[i]
		
	index = -1
	for f in real_select:
		index += 1
		if not f.has("select_name"):
			f["select_name"] = f["Column Name"]
			
		if field_as_index.get(index, "") != "":
			f["field_as"] = field_as_index[index]
		else:
			f["field_as"] = f["Column Name"]
			
		f["name_4_computing"] = f["select_name"]
	return real_select
	
func __get_table_defination(db_name: String, table_name: String):
	return {
		"columns": GDSQL.RootConfig.get_table_columns(db_name, table_name),
		"valid_if_not_exist": GDSQL.RootConfig.get_table_valid_if_not_exist(db_name, table_name),
	}
	
func __get_table_columns(db_name: String, table_name: String, table_alias: String):
	var columns: Array
	var defination = __get_table_defination(db_name, table_name)
	if defination:
		columns = defination["columns"]
		
	if columns != null:
		columns = columns.duplicate(true)
		for i in columns:
			i["db_path"] = GDSQL.RootConfig.get_database_data_path(db_name)
			i["table_name"] = table_name
			i["is_field"] = true
			i["table_alias"] = table_alias
			
	return columns
	
func __get_table_column_defination(db_name: String, table_name: String, table_alias: String, column_name: String):
	var defination = __get_table_defination(db_name, table_name)
	var columns = defination["columns"] if defination else null
	var column
	if columns != null:
		for i in columns:
			if i["Column Name"] == column_name:
				column = i
				break
				
	if column != null:
		column = (column as Dictionary).duplicate(true)
		column["db_path"] = GDSQL.RootConfig.get_database_data_path(db_name)
		column["table_name"] = table_name
		column["is_field"] = true
		column["table_alias"] = table_alias
		
	return column
	
## 只有在编辑器模式时才可能返回true
func need_user_enter_password() -> bool:
	return not __request_password.is_empty()
	
func _handle_defualt_password():
	__request_password.clear()
	# 在编辑器模式，要求用户输入密码
	if mgr and Engine.is_editor_hint():
		if mgr.need_request_password(get_db(), get_table(), get_password()):
			__request_password.push_back(true)
	elif _PASSWORD.is_empty():
		_PASSWORD = GDSQL.RootConfig.get_database_dek(__db_name)
		if _PASSWORD.is_empty():
			_PASSWORD = GDSQL.RootConfig.get_table_dek(__db_name, __table)
	elif _PASSWORD is PackedByteArray:
		pass # Skip
	else:
		# 既然用户输入了密码，那就验证一下吧
		var encrypted_dek = GDSQL.RootConfig.get_database_encrypted_dek(__db_name)
		if encrypted_dek == "":
			encrypted_dek = GDSQL.RootConfig.get_table_encrypted_dek(__db_name, __table)
			if encrypted_dek == "":
				# 本来没密码，非要输入一个错的密码，也不行。
				_assert_false("query", "Incorrect password!")
				return ERR_UNAUTHORIZED
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(encrypted_dek, _PASSWORD)
		if not recovered_dek:
			_assert_false("query", "Incorrect password!")
			return ERR_UNAUTHORIZED
	return OK
	
## 执行。注意：在union的情况下，会自动执行第一个BaseDao的query方法。
func query() -> GDSQL.QueryResult:
	var begin_time = Time.get_unix_time_from_system()
	if not __db_name or not __db_path:
		return _assert_false("query", "database is empty")
	if __table == "":
		return _assert_false("query", "table is empty")
	if __cmd == "":
		return _assert_false("query", "command is empty")
		
	_set_primary_and_autoincre()
	
	if __parent_union:
		return __parent_union.get_ref().query()
		
	var err = _handle_defualt_password()
	if err != OK:
		return null
	if need_user_enter_password():
		return null
		
	var path = GDSQL.RootConfig.get_table_data_path(__db_name, __table)
	var result = GDSQL.QueryResult.new()
	match __cmd:
		"select":
			var ret = ___select()
			if need_user_enter_password():
				return null
			result._has_head = __need_head
			result._columns_count = __select_query_columns_count
			result._cost_time = Time.get_unix_time_from_system() - begin_time
			if not __err.is_empty():
				result._err = "\n".join(__err)
			if typeof(ret) == TYPE_NIL:
				if __collect_lack_table_enabled and not __lack_table.is_empty():
					result._lack_tables = __lack_table.duplicate()
					reset()
					return result
				return _assert_false("query:%s" % __cmd, "Error occur!")
				
			result._data = ret
			reset()
			return result
		"insert_into", "insert_ignore", "insert_or_update", "replace_into":
			if __data.is_empty():
				return _assert_false("query:%s" % __cmd, "Data is empty")
			if __primary_key == null or __primary_key == "":
				return _assert_false("query:%s" % __cmd, "Primary key is empty")
			# 检查数据类型是否正确
			var columns_def = __get_table_defination(__db_name, __table)["columns"]
			
			# __data是数组的情况下，需要转成字典格式
			if __data is Array:
				var tmp = __data
				__data = {}
				for i in tmp.size():
					__data[columns_def[i]["Column Name"]] = tmp[i]
					
			for col in columns_def:
				var col_name = col["Column Name"]
				if __data.has(col_name):
					if typeof(__data[col_name]) != col["Data Type"]:
						var v1 = type_convert(__data[col_name], col["Data Type"])
						var v2 = type_convert(v1, typeof(__data[col_name]))
						# 转化过程有损失时，抛出错误
						if v2 != __data[col_name]:
							return _assert_false("query:%s" % __cmd, 
							"data type of %s is not %s" % \
							[col_name, type_string(col["Data Type"])])
						__data[col_name] = v1
						
			var conf: GDSQL.ImprovedConfigFile = _get_conf(__db_name, __table, _PASSWORD)
			if conf == null:
				return _assert_false("query:%s" % __cmd, "load conf err!")
			var primary_value = str(__data.get(__primary_key))
			var insert = true # 是insert模式还是update模式。只有insert_or_update时会涉及
			if primary_value == null:
				# 这几种插入操作都需要主键存在，用户要不就直接在data里写好了主键，要不就设置为自增，否则报错
				if __autoincrement_keys.has(__primary_key) or __autoincrement_keys_def.has(__primary_key):
					pass # 后面会统一把所有需要自增的键一起处理
				else:
					result._err = "key 'PRIMARY' is missing for %s" % __cmd
					push_error(result.get_err())
					result._cost_time = Time.get_unix_time_from_system() - begin_time
					return result
			else:
				if conf.has_section(primary_value):
					if __cmd == "insert_ignore":
						# 数据存在，不用插入
						result._cost_time = Time.get_unix_time_from_system() - begin_time
						return result
					elif __cmd == "insert_or_update":
						# 数据存在，只更新部分字段，所以把旧数据的其他字段塞到新数据里
						var old_data = conf.get_section_values(primary_value)
						if not old_data.is_empty():
							insert = false
						for field in old_data:
							if not __duplicate_update_fields.has(field):
								__data[field] = old_data.get(field)
					elif __cmd == "replace_into":
						# 数据存在，删除旧数据，插入新数据
						conf._erase_section(primary_value)
						result._affected_rows += 1
					else:
						result._err = "Duplicate entry '%s' for key 'PRIMARY'" % primary_value
						push_error(result.get_err())
						result._cost_time = Time.get_unix_time_from_system() - begin_time
						return result
						
			# 自增:找到当前最大的
			var datas: Array[Dictionary] = conf.get_all_section_values() # TODO 优化，是否需要？不过大部分情况下是需要的
			var autoincrement_keys = __autoincrement_keys.duplicate()
			autoincrement_keys.merge(__autoincrement_keys_def) # 合并字典，不要重复计算
			for field in autoincrement_keys:
				if __data.get(field) == null or (__data.get(field) is int and __data.get(field) == 0):
					for data in datas:
						if data.get(field) != null and data.get(field) >= autoincrement_keys.get(field):
							autoincrement_keys[field] = data.get(field)
							
			for field in autoincrement_keys:
				if __data.get(field) == null or (__data.get(field) is int and __data.get(field) == 0):
					__data[field] = autoincrement_keys.get(field) + 1
					result._generated_keys[field] = __data[field]
					
			# insert模式下，对于有表结构定义的数据，每个字段都必须插入，也不能有多余的字段。需在自增之后检查。
			if insert and not columns_def.is_empty():
				var col_names = []
				for col in columns_def:
					var col_name = col["Column Name"]
					col_names.push_back(col_name)
					if __data.has(col_name):
						continue
						
					if col["Default(Expression)"] != "":
						__data[col_name] = GDSQL.GDSQLUtils.evaluate_command(null, col["Default(Expression)"])
						result._generated_keys[col_name] = __data[col_name]
						continue
						
					if col["NN"]:
						result._affected_rows = 0
						result._err = "field '%s' needs to be set" % col_name
						push_error(result.get_err())
						result._cost_time = Time.get_unix_time_from_system() - begin_time
						return result
					else:
						__data[col_name] = type_convert("", col["Data Type"])
						if __data[col_name] == null:
							result._affected_rows = 0
							result._err = \
							"field '%s' is implicitly cast to null which is not support by ConfigFile." % col_name
							push_error(result.get_err())
							result._cost_time = Time.get_unix_time_from_system() - begin_time
							return result
						
				if __data.size() != columns_def.size():
					result._affected_rows = 0
					result._err = "invalid field(s): %s" % ",".join(
						__data.keys().filter(func(v): return not col_names.find(v)))
					push_error(result.get_err())
					result._cost_time = Time.get_unix_time_from_system() - begin_time
					return result
					
			# 检查唯一性：只关注新插入的数据是否与旧数据重复
			for col in columns_def:
				if not col["UQ"]:
					continue
				var col_name = col["Column Name"] 
				for data in datas:
					if __data[col_name] == data.get(col_name, null):
						result._affected_rows = 0
						result._err = "Duplicate field value '%s' for key '%s'" % \
							[var_to_str(__data[col_name]), col_name]
						push_error(result.get_err())
						result._cost_time = Time.get_unix_time_from_system() - begin_time
						return result
						
			# 插入
			conf.set_values(str(__data.get(__primary_key)), __data)
			if __auto_commit:
				GDSQL.ConfManager.save_conf_by_origin_password_or_dek(path)
			result._affected_rows += 1
			result._last_insert_id = __data.get(__primary_key)
			result._cost_time = Time.get_unix_time_from_system() - begin_time
			if not __err.is_empty():
				result._err = "\n".join(__err)
			reset()
			return result
			
		"update":
			if __data.is_empty():
				return _assert_false("query:%s" % __cmd, "Data is empty")
			if __where.is_empty():
				return _assert_false("query:%s" % __cmd, 
				"Condition is empty. This limitition if for safety.")
				
			var columns_def = __get_table_defination(__db_name, __table)["columns"]
			# 检查数据类型是否正确. __enable_evaluate为true时，需要计算之后才能判断
			if not __enable_evaluate:
				for col in columns_def:
					var col_name = col["Column Name"]
					if __data.has(col_name):
						var new_val = __data[col_name]
						if typeof(new_val) != col["Data Type"]:
							var v1 = type_convert(new_val, col["Data Type"])
							var v2 = type_convert(v1, typeof(new_val))
							# 转化过程有损失时，抛出错误
							if v2 != new_val:
								return _assert_false("query:%s" % __cmd, 
								"data type of %s is not %s" % [col_name, type_string(col["Data Type"])])
							__data[col_name] = v1
							
			# 不能有多余的字段
			var invalid_key = []
			for key in __data:
				var find = false
				for col in columns_def:
					if key == col["Column Name"]:
						find = true
						break
				if not find:
					invalid_key.push_back(key)
			if not invalid_key.is_empty():
				return _assert_false("query:%s" % __cmd, "Invalid field(s): %s." % ",".join(invalid_key))
				
			# 筛选出要更新的数据
			var primary = "__PRIMARY_1355--5--__" # 让数据库把主键存到这个键里，祈祷用户没有用到这个字段
			__need_post_porcess = false # update一定是单表，用内部返回模式返回数据
			var datas = ___select(primary)
			if need_user_enter_password():
				return null
			if datas == null:
				if not __err.is_empty():
					result._err = "\n".join(__err)
				return result
				
			if datas.is_empty():
				result._cost_time = Time.get_unix_time_from_system() - begin_time
				if not __err.is_empty():
					result._err = "\n".join(__err)
				return result
				
			# 更新数据
			var conf: GDSQL.ImprovedConfigFile = _get_conf(__db_name, __table, _PASSWORD)
			if conf == null:
				return _assert_false("query:%s" % __cmd, "Load conf err!")
			for data in datas:
				data = data[__table_alias] # 未经过后处理的肯定是用表名分类的结构
				var a_names = []
				var a_values = []
				for i: String in data:
					# i 是 table_alias，排除 i 为空字符串的情况。
					if i != "":
						a_names.push_back(i)
						a_values.push_back(data[i])
						
				# 计算值。例如id = id + 1
				var a_data = __data
				if __enable_evaluate:
					# NOTICE 该过程会改变__data
					a_data = _evaluate_data(a_names, a_values, columns_def)
					if not a_data is Dictionary:
						result._affected_rows = 0
						result._err = "Error occur."
						push_error(result.get_err())
						result._cost_time = Time.get_unix_time_from_system() - begin_time
						GDSQL.ConfManager.remove_conf(path) # discard possible changes
						return result
						
				var primary_value = str(data.get(primary))
				var affected = false
				# update主键，可能要替换主键
				if a_data.has(__primary_key):
					var value = a_data.get(__primary_key)
					if primary_value != str(value):
						# 判断主键是否被占用了
						if conf.has_section(str(value)):
							result._affected_rows = 0
							result._err = "Duplicate entry '%s' for key 'PRIMARY'" % value
							push_error(result.get_err())
							result._cost_time = Time.get_unix_time_from_system() - begin_time
							GDSQL.ConfManager.remove_conf(path) # discard possible changes
							return result
							
						conf._erase_section(primary_value)
						data[__primary_key] = value # 先只替换主键及主键值
						primary_value = str(value)
						data.erase(primary)
						conf.set_values(primary_value, data)
						affected = true
						
				for field in a_data:
					# 主键前面处理过了，这里跳过
					if field == __primary_key:
						continue
					var value = a_data.get(field)
					if conf.get_value(primary_value, field) != value:
						conf._set_value(primary_value, field, value)
						affected = true
				if affected:
					result._affected_rows += 1
					
			if __auto_commit and result._affected_rows > 0:
				GDSQL.ConfManager.save_conf_by_origin_password_or_dek(path)
			result._cost_time = Time.get_unix_time_from_system() - begin_time
			if not __err.is_empty():
				result._err = "\n".join(__err)
			reset()
			return result
			
		"delete_from":
			var conf: GDSQL.ImprovedConfigFile = _get_conf(__db_name, __table, _PASSWORD)
			if conf == null:
				return _assert_false("query:%s" % __cmd, "Load conf err!")
				
			if __where.is_empty():
				result._affected_rows = conf.get_sections().size()
				conf._clear()
			else:
				# 筛选出要删除的数据
				var primary = "__PRIMARY_1355--5--__" # 让数据库把主键存到这个键里，祈祷用户没有用到这个字段
				__need_post_porcess = false # update一定是单表，用内部返回模式返回数据
				var datas = ___select(primary)
				if need_user_enter_password():
					return null
				if datas == null:
					if not __err.is_empty():
						result._err = "\n".join(__err)
					return result
					
				if datas.is_empty():
					result._cost_time = Time.get_unix_time_from_system() - begin_time
					if not __err.is_empty():
						result._err = "\n".join(__err)
					return result
					
				# 删除数据
				for data in datas:
					data = data[__table_alias] # 未经过后处理的肯定是用表名分类的结构
					var section = str(data.get(primary))
					conf._erase_section(section)
					result._affected_rows += 1
					
			if __auto_commit and result._affected_rows > 0:
				GDSQL.ConfManager.save_conf_by_origin_password_or_dek(path)
				
			result._cost_time = Time.get_unix_time_from_system() - begin_time
			if not __err.is_empty():
				result._err = "\n".join(__err)
			reset()
			return result
			
	result._cost_time = Time.get_unix_time_from_system() - begin_time
	return result
	
## query过程中，可能缺少某些表的数据，通过该方法获取
func get_lack_table() -> Array:
	return __lack_table
	
func _evaluate_data(p_names: Array, p_values: Array, columns_def: Array) -> Dictionary:
	var a_data = __data.duplicate()
	for col in columns_def:
		var col_name = col["Column Name"]
		if a_data.has(col_name):
			var new_val = a_data[col_name]
			var try = new_val
			if new_val is String:
				try = str_to_var(new_val)
				if typeof(try) == TYPE_NIL:
					try = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(null, new_val, p_names, p_values)
					if typeof(try) == TYPE_NIL:
						if col["Data Type"] == TYPE_STRING:
							continue
						else:
							try = new_val
							
			if typeof(try) != col["Data Type"]:
				var v1 = type_convert(try, col["Data Type"])
				var v2 = type_convert(v1, typeof(try))
				# 转化过程有损失时，抛出错误
				if v2 != try:
					return _assert_false("query:%s" % __cmd, 
						"data type of %s is not %s" % [col_name, type_string(col["Data Type"])])
				a_data[col_name] = v1
			else:
				a_data[col_name] = try
	return a_data
	
func _get_cond(need_where: bool, new_line = false) -> String:
	#var cond = ""
	#for i in __where:
		#if cond != "":
			#cond += " and "
		#cond += "(" + i + ")"
	var cond = " and ".join(__where)
	
	if cond == "":
		return cond
		
	if not need_where:
		if new_line:
			return "\n" + cond
		return cond
		
	if new_line:
		return "\nwhere " + cond
	return " where " + cond
	
func _get_order_by(need_order_by: bool, new_line = false) -> String:
	if __order_by.is_empty():
		return ""
		
	var arr = []
	for i in __order_by:
		arr.push_back("%s %s" % [i[0], "asc" if i[1] == GDSQL.ORDER_BY.ASC else "desc"])
	var s = ", ".join(arr)
	
	if not need_order_by:
		if new_line:
			return "\n" + s
		return s
		
	if new_line:
		return "\norder by " + s
	return " order by " + s
	
func _get_limit(new_line = false) -> String:
	if __limit < 0 or __offset < 0:
		return ""
		
	if new_line:
		return "\n limit %d, %d" % [__offset, __limit]
	return " limit %d, %d" % [__offset, __limit]
	
func get_cmd() -> String:
	return __cmd
	
## 获取正正执行的语句
func get_query_cmd() -> String:
	var a_table = __table.substr(0, __table.length() - GDSQL.RootConfig.DATA_EXTENSION.length())
	match __cmd:
		"select":
			return "select %s from %s%s%s%s%s%s%s" % [
				__select_str, 
				a_table,
				"" if __table_alias == "" else " " + __table_alias,
				"" if __left_join == null else "\n" + "\n".join(__left_join.get_query_cmds()),
				_get_cond(true, false) if __left_join == null else _get_cond(true, true),
				"" if __union_all == null else "\nunion all " + __union_all.get_query_cmd(),
				_get_order_by(true, false) if __union_all == null and __left_join == null else _get_order_by(true, true),
				_get_limit(false) if __union_all == null and __left_join == null else _get_limit(true)
			]
		"insert_into":
			return "insert into %s (%s) values (%s)" \
				% [a_table, ", ".join(__data.keys()), ", ".join(__data.values().map(func(v): return var_to_str(v)))]
		"insert_ignore":
			return "insert ignore into %s (%s) values (%s)" \
				% [a_table, ", ".join(__data.keys()), ", ".join(__data.values().map(func(v): return var_to_str(v)))]
		"insert_or_update":
			var arr = []
			for key in __data:
				arr.push_back(key + " = " + var_to_str(__data[key]))
			return "insert into %s (%s) values (%s) on duplicate key update %s" % \
				[a_table, ", ".join(__data.keys()), ", ".join(__data.values().map(func(v): return var_to_str(v))), ", ".join(arr)]
		"update":
			var arr = []
			for key in __data:
				arr.push_back(key + " = " + var_to_str(__data[key]))
			return "update %s set %s%s" % [a_table, ", ".join(arr), _get_cond(true)]
		"delete_from":
			return "delete from %s%s" % [a_table, _get_cond(true)]
	return ""
	
func reset(_force = false):
	return # to let dao reusable.
	#__lack_table.clear()
	#__err.clear()
	#if force == false and Engine.is_editor_hint():
		#return
	#__request_password.clear()
	#__database = ""
	#__cmd = ""
	#__select_str = ""
	#__select.clear()
	#__field_as_index.clear()
	#__table = ""
	#__table_alias = ""
	#if __data:
		#__data.clear()
	#__where.clear()
	#__group_by.clear()
	#__order_by.clear()
	#__offset = -1
	#__limit = -1
	#__duplicate_update_fields.clear()
	#__primary_key = ""
	#__primary_key_def = ""
	#__autoincrement_keys.clear()
	#__autoincrement_keys_def.clear()
	#__union_all = null
	#__parent_union = null
	#if __left_join:
		#__left_join.clear_chain()
		#__left_join = null
	#__need_post_porcess = true
	#__need_head = false
	#__auto_commit = true
	#__table_conf_path.clear()
	#__enable_evaluate = false
	#__sub_select_index = -1
	#__select_query_columns_count = 0
	#__sub_queries.clear()
	#__input_names.clear()
	#__final_input_names.clear()
	#__inputs.clear()
	#__simplify_exp_cache.clear()
	#__collect_lack_table_enabled = false
	#regex_field_map.clear()
	#mgr = null
	
class ExpressionCacheNode extends RefCounted:
	var key
	var value: Variant
	var prev: ExpressionCacheNode
	var next: ExpressionCacheNode
	
class ExpressionLRULink extends RefCounted:
	var cache: Dictionary
	var capacity: int
	var head: ExpressionCacheNode = ExpressionCacheNode.new()
	var tail: ExpressionCacheNode = ExpressionCacheNode.new()
	
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
		var node = cache[key] as ExpressionCacheNode
		move_to_tail(node)
		return node.value
		
	func remove_value(key):
		if not has_key(key):
			return
		var node = cache[key] as ExpressionCacheNode
		remove_node(node)
		cache.erase(key)
		
	func put_value(key, value: Variant):
		if cache.has(key):
			var node = cache[key] as ExpressionCacheNode
			node.value = value
			move_to_tail(node)
		else:
			var node = ExpressionCacheNode.new()
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
				
	func add_to_tail(node: ExpressionCacheNode):
		var prev_node = tail.prev
		prev_node.next = node
		node.prev = prev_node
		node.next = tail
		tail.prev = node
		
	func remove_node(node: ExpressionCacheNode):
		var prev_node = node.prev
		var next_node = node.next
		prev_node.next = next_node
		next_node.prev = prev_node
		
	func move_to_tail(node: ExpressionCacheNode):
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
