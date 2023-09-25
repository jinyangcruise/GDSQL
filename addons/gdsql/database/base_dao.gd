extends RefCounted
class_name BaseDao

var _PASSWORD = "" ## 数据表密码

var __database = "user://" ## 【外部请勿使用】数据库路径
var __cmd: String = "" ## 【外部请勿使用】命令
var __select: Array[String] = [] ## 【外部请勿使用】select哪些字段
var __field_as: Dictionary = {} ## 【外部请勿使用】字段别名
var __table: String = "" ## 【外部请勿使用】表名（带extension的）
var __table_alias: String = "" # 【外部请勿使用】别名
var __data: Dictionary ## 【外部请勿使用】更新数据使用
var __where: Array = [] ## 【外部请勿使用】筛选数据条件
var __order_by: Array = [] ## 【外部请勿使用】排序条件
var __offset: int = -1 ## 【外部请勿使用】select返回数据截取起始位置
var __limit: int = -1 ## 【外部请勿使用】select返回数据截取长度
var __duplicate_update_fields: Array = [] ## 【外部请勿使用】主键重复时更新哪些字段
var __primary_key: String = "" ## 【外部请勿使用】主键是什么
var __primary_key_def: String = "" ## 【外部请勿使用】定义文件中的主键
var __autoincrement_keys: Dictionary = {} ## 【外部请勿使用】自增键有哪些
var __autoincrement_keys_def: Dictionary = {} ## 【外部请勿使用】定义文件中的自增键
var __union_all: BaseDao ## 【外部请勿使用】union的单元
var __parent_union: BaseDao ## 【外部请勿使用】被uion的单元
#var __left_join_tables: Dictionary = {} ## 【外部请勿使用】联表查询的表相关信息
var __left_join: LeftJoin ## 【外部请勿使用】第一个联表对象（获取第N个联表对象需要通过第N-1个联表对象来获取）
var __need_post_porcess: bool = true ## 【外部请勿使用】select最终返回数据时处理：是否按照用户所需的字段进行精简
var __need_head: bool ## 【外部请勿使用】select返回的数据是否包含一行表头（在第一行）
var __auto_commit: bool = true ## 【外部请勿使用】自动提交标志
var __root_config: ImprovedConfigFile ## 【外部请勿使用】临时获取数据库定义文件
var __config: ImprovedConfigFile ## 【外部请勿使用】临时为了获取数据库定义文件

const ROOT_CONFIG_PATH = "res://addons/gdsql/config/config.cfg"
const DATA_EXTENSION = ".gsql"
const CONF_EXTENSION = ".cfg"

var __CONF_MANAGER: ConfManagerClass
var mgr: GDSQLWorkbenchManagerClass

enum ORDER_BY { ASC, DESC }

func _init():
	if Engine.has_singleton("ConfManager"):
		__CONF_MANAGER = Engine.get_singleton("ConfManager")
	else:
		__CONF_MANAGER = ConfManager
		
	if Engine.has_singleton("GDSQLWorkbenchManager"):
		mgr = Engine.get_singleton("GDSQLWorkbenchManager")
	else:
		mgr = GDSQLWorkbenchManagerClass.new()

func use_db(database: String) -> BaseDao:
	__database = database
	return self
	
func use_user_db() -> BaseDao:
	__database = "user://"
	return self
	
func use_conf_db() -> BaseDao:
	__database = "res://src/config/"
	return self
	
func set_password(password: String) -> BaseDao:
	_PASSWORD = password
	return self
	
## 是否自动提交（保存文件），不提交只是在内存中更改数据
func auto_commit(auto: bool) -> BaseDao:
	__auto_commit = auto
	return self
	
func _assert(action: String, success: bool, msg: String) -> bool:
	if not success:
		if Engine.is_editor_hint():
			mgr.create_accept_dialog(msg)
			mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(), action, msg)
		push_error(msg)
		return false
	return true
	
## 手动提交（保存到文件）
func commit() -> void:
	assert(_assert("commit", __database != "", "database is empty"))
	assert(_assert("commit", __table != "", "table name is empty"))
	var path = __database + __table
	var conf: ImprovedConfigFile = __CONF_MANAGER.get_conf(path, _PASSWORD)
	assert(_assert("commit", conf != null, "load conf err!"))
	__CONF_MANAGER.save_conf_by_origin_password(path)
	reset()
	
## 查询数据子句
## something: 查询字段语句，即数据库查询语句select和from之间的语句
## need_head: 是否需要表头。传true，如果查询到了数据，那么返回数据的第一行会是一个表头表示每列是什么字段。union表该参数无效，等价于false。
## 注意：若联表查询还要求返回平数据，则query后会在每条数据的每个字段前加上表的别名和小数点。例如：[["t1.a": xx, "t2.m": yy]]
## 这个方法会预处理每个要求的字段和字段的别名（如有），但不会马上在这里处理星号，而是推迟到query的时候才处理。
func select(someting: String, need_head: bool) -> BaseDao:
	assert(_assert("select", __cmd == "" or __cmd == "select", "already set command %s" % __cmd))
	#if __parent_union and need_head:
		#push_warning("union table cannot have head but the param `need_head` is true, this param will be ignored")
	__cmd = "select"
	__select = []
	__field_as = {}
	__need_head = need_head
	someting = someting.strip_edges()
	# 拆分select的字段。不能简单用split(",")，因为字段有可能是函数调用，它不支持正则（至少Godot 4.1不支持）
	# 下面的方案支持类似这样的情况："*,a.uname.contains(),aa.level, t.img, at.icon(1, 2, \"a, b\"), t_user.u, y.call()"
	var regex = RegEx.new()
	#regex.compile(",\\s*(?![^()]*\\))") # 匹配逗号的位置，括号内的逗号不匹配
	# 匹配逗号的位置，括号、引号内的逗号都不匹配
	regex.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	var matches = regex.search_all(someting)
	
	# 别名
	var regex_2 = RegEx.new()
	regex_2.compile("[\\s]+as[\\s]+([0-9a-zA-Z_]+)$")
	
	if not matches.is_empty():
		
		var start = 0
		for i in matches:
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var field_str = someting.substr(start, i.get_start() - start).strip_edges()
			start = i.get_end()
			
			# 有可能取了别名，例如t_user.icon(1, 2, \"a, b\") as iii
			var m = regex_2.search(field_str)
			if m:
				# 实际要求的式子，例子中的t_user.icon(1, 2, \"a, b\")
				field_str = field_str.substr(0, m.get_start(0))
				__field_as[field_str] = m.get_string(1) # 别名做个映射，例子中的iii
			
			__select.push_back(field_str)
			
		# 别忘了还有最后一个逗号到最后
		if start < someting.length():
			var field_str = someting.substr(start).strip_edges()
			
			var m = regex_2.search(field_str)
			if m:
				field_str = field_str.substr(0, m.get_start(0))
				__field_as[field_str] = m.get_string(1)
				
			__select.push_back(field_str)
	# 没有逗号分割，*或者某个单独的字段
	else:
		var m = regex_2.search(someting)
		if m:
			# 实际要求的式子，例子中的t_user.icon(1, 2, \"a, b\")
			someting = someting.substr(0, m.get_start(0))
			__field_as[someting] = m.get_string(1) # 别名做个映射，例子中的iii
		__select.push_back(someting)
		
	return self
	
## union之后的BaseDao可以进行select_same，表示与父BaseDao查询相同的字段。
## 该方法是为了简化用户输入。
func select_same() -> BaseDao:
	assert(_assert("select_same", __parent_union != null, "must have parent union!"))
	assert(_assert("select_same", __cmd == "", "already set command %s" % __cmd))
	__cmd = "select"
	__select = __parent_union.__select.duplicate()
	__field_as = __parent_union.__field_as.duplicate()
	__need_head = false
	return self
	
## 同时设置表名和别名
func from(table: String, alias: String = "") -> BaseDao:
	assert(_assert("from", __database != null and __database != "", "please set db first!"))
	__table = table
	__table_alias = alias
	__primary_key_def = ""
	__autoincrement_keys_def = {}
	var defination = __get_table_defination(__database, __table)
	if defination != null and !defination.is_empty():
		for column in defination:
			if column["PK"]:
				__primary_key_def = column["Column Name"]
				__primary_key = __primary_key_def
			if column["AI"]:
				__autoincrement_keys_def[column["Column Name"]] = 0
	return self
	
## 单独设置表名
func set_table(table: String) -> BaseDao:
	from(table, __table_alias)
	return self
	
## 单独设置表别名
func set_table_alias(alias: String) -> BaseDao:
	__table_alias = alias
	return self
	
func values(data: Dictionary) -> BaseDao:
	assert(_assert("values", __cmd.begins_with("insert") or __cmd.begins_with("replace"), 
		"'values' can only be used after 'insert' or 'replace'"))
	__data = data
	return self
	
func sets(data: Dictionary) -> BaseDao:
	assert(_assert("sets", __cmd == "update", "'sets' can only be used after 'update'"))
	__data = data
	return self
	
func insert_into(table: String) -> BaseDao:
	assert(_assert("insert_into", __cmd == "", "already set command %s" % __cmd))
	__cmd = "insert_into"
	set_table(table)
	return self
	
func insert_ignore(table: String) -> BaseDao:
	assert(_assert("insert_ignore", __cmd == "", "already set command %s" % __cmd))
	__cmd = "insert_ignore"
	set_table(table)
	return self
	
func insert_or_update(table: String) -> BaseDao:
	assert(_assert("insert_or_update", __cmd == "", "already set command %s" % __cmd))
	__cmd = "insert_or_update"
	set_table(table)
	return self
	
func replace_into(table: String) -> BaseDao:
	assert(_assert("replace_into", __cmd == "", "already set command %s" % __cmd))
	__cmd = "replace_into"
	set_table(table)
	return self
	
func update(table: String) -> BaseDao:
	assert(_assert("update", __cmd == "", "already set command %s" % __cmd))
	assert(_assert("update", __table_alias == "", "table alias must be empty"))
	__cmd = "update"
	set_table(table)
	return self
	
func delete_from(table: String) -> BaseDao:
	assert(_assert("delete_from", __cmd == "", "already set command %s" % __cmd))
	__cmd = "delete_from"
	set_table(table)
	return self
	
## 如果多次调用，那么这些条件将是`and`的关系。如需避免多次调用，请使用set_where
func where(cond: String) -> BaseDao:
	assert(_assert("where", __cmd == "select" or __cmd == "update" or __cmd == "delete_from", 
		"'where' can only be used after 'select' or 'update' or 'delete_from'"))
	cond = cond.strip_edges()
	if not cond.is_empty():
		__where.push_back(cond)
	return self
	
func set_where(cond: String) -> BaseDao:
	assert(_assert("where", __cmd == "select" or __cmd == "update" or __cmd == "delete_from", 
		"'where' can only be used after 'select' or 'update' or 'delete_from'"))
	cond = cond.strip_edges()
	__where.clear()
	if not cond.is_empty():
		__where.push_back(cond)
	return self
	
## 返回一个新的baseDao
func union_all() -> BaseDao:
	assert(_assert("union_all", __cmd == "select", "'union_all' can only be used after 'select'"))
	var bd = BaseDao.new()
	__union_all = bd
	bd.__parent_union = self
	return bd
	
## 设置unionall对象，返回的仍旧是自己
func set_union_all(base_dao: BaseDao) -> BaseDao:
	assert(_assert("set_union_all", __cmd == "select", "'union_all' can only be used after 'select'"))
	__union_all = base_dao
	base_dao.__parent_union = self
	return self
	
func remove_union_all(base_dao: BaseDao) -> bool:
	if __union_all == base_dao:
		__union_all.__parent_union = null
		__union_all = null
		return true
	return false
	
func has_union_all(base_dao: BaseDao) -> bool:
	return __union_all == base_dao
	
## 注意该方法具有嵌套效果，在union的时候，链条中某个环节的order_by会对后面所有环节进行排序
func order_by(field: String, order: ORDER_BY) -> BaseDao:
	assert(_assert("order_by", __cmd == "select", "'order_by' can only be used after 'select'"))
	field = field.strip_edges()
	if not field.is_empty():
		__order_by.push_back([field, order])
	return self
	
## 注意，若用该方法，就一次性传入字符串。如果多次使用，只有最后一次的有效。
func order_by_str(string: String) -> BaseDao:
	assert(_assert("order_by_str", __cmd == "select", "'order_by' can only be used after 'select'"))
	# 清空
	__order_by = []
	var regex = RegEx.new()
	# 匹配逗号的位置，括号、引号内的逗号都不匹配
	regex.compile(",(?=(([^']*'){2})*[^']*$)(?=(([^\"]*\"){2})*[^\"]*$)(?![^()]*\\))")
	var matches = regex.search_all(string)
	var arr = []
	if not matches.is_empty():
		var start = 0
		for i in matches:
			start = i.get_end()
			# 知道逗号的起始位置，就可以截取逗号前的位置到上一个逗号的结束位置
			var a_order = string.substr(start, i.get_start() - start).strip_edges()
			arr.push_back(a_order)
			
		# 别忘了还有最后一个逗号到最后
		if start < string.length():
			var a_order = string.substr(start).strip_edges()
			arr.push_back(a_order)
	else:
		arr.push_back(string)
		
	for a_order in arr:
		if a_order.ends_with("asc") or a_order.ends_with("ASC"):
			__order_by.push_back([a_order.substr(0, a_order.length() - 3).strip_edges(), ORDER_BY.ASC])
		elif a_order.ends_with("desc") or a_order.ends_with("DESC"):
			__order_by.push_back([a_order.substr(0, a_order.length() - 4).strip_edges(), ORDER_BY.DESC])
		else:
			__order_by.push_back([a_order, ORDER_BY.ASC])
			
	return self
	
## 注意该方法具有嵌套效果，在union的时候，链条中某个环节的limit会对后面所有环节进行limit
func limit(a_offset: int, a_limit: int) -> BaseDao:
	assert(_assert("limit", __cmd == "select", "'limit' can only be used after 'select'"))
	assert(_assert("limit", a_offset >= 0 and a_limit > 0, 
		"offset must not less than 0 and limit must larger than 0"))
	__offset = a_offset
	__limit = a_limit
	return self
	
func on_duplicate_update(fields: Array[String]) -> BaseDao:
	assert(_assert("on_duplicate_update", __cmd == "update" or __cmd == "insert_or_update", 
		"'on_duplicate_update' can only be used after 'update'"))
	__duplicate_update_fields = fields
	return self
	
## 指定主键（适用于没有定义文件的表。如果表有定义文件，则勿设置其他键为主键。）
func primary_key(a_key: String, auto_increment: bool = true) -> BaseDao:
	assert(_assert("primary_key", __primary_key_def.is_empty() or a_key == __primary_key_def, 
		"this table has defination of primary key, do not set a different primary key"))
	__primary_key = a_key
	if auto_increment:
		__autoincrement_keys[a_key] = 0
	return self
	
## 增加自增字段
## 注意1：如果用户自己设定了某个非主键自增字段的值，则按用户设置的值为准，不会自增；
## 注意2：如果用户命令是insert_or_update，只有在新增数据的情况下才可能（也关系到注意1的情况）自增
## 注意3：如果操作的表的定义文件中该字段并非自增字段，不影响本次操作临时把其当成自增字段。
func add_auto_increment_key(a_key: String) -> BaseDao:
	assert(_assert("add_auto_increment_key", __cmd.begins_with("insert") or __cmd.begins_with("replace"), 
		"'add_auto_increment_key' can only be used after 'insert' or 'replace'"))
	__autoincrement_keys[a_key] = 0
	return self
	
func left_join(db: String, table: String, alias: String, cond: String, password: String) -> BaseDao:
	assert(_assert("left_join", __cmd.begins_with("select"), "left_join must use after select"))
	assert(_assert("left_join", __table_alias != "", "main table must have alias name before use 'left join'"))
	assert(_assert("left_join", 
		alias != __table_alias and (__left_join == null or not __left_join.chain_has_alias(alias)), 
		"duplicate table alias"))
	if db == "":
		db = __database
	var regex = RegEx.new()
	regex.compile("(\\b[0-9a-zA-Z_]+\\b)\\.[0-9a-zA-Z_\\-]+")
	var dependencies = [] # 依赖的表
	var matchs = regex.search_all(cond)
	for i in matchs:
		var t = i.get_string(1)
		if t != alias and !dependencies.has(t):
			dependencies.push_back(t)
			
	var left_join_obj: LeftJoin
	if __left_join == null:
		__left_join = LeftJoin.new()
		left_join_obj = __left_join
	else:
		left_join_obj = __left_join.create_left_join_to_end()
	left_join_obj.set_db(db)
	left_join_obj.set_password(password)
	left_join_obj.set_table(table)
	left_join_obj.set_alias(alias)
	left_join_obj.set_condition(cond)
	left_join_obj.set_dependencies(dependencies)
	return self
	
func set_left_join(left_join_obj: LeftJoin) -> BaseDao:
	__left_join = left_join_obj
	return self
	
func remove_left_join(left_join_obj: LeftJoin) -> bool:
	if __left_join == left_join_obj:
		__left_join = null
		return true
	return false
	
## 联表查询，简化用户输入参数，使用与主表相同的数据库和密码
func left_join_use_same_db_and_pass(table: String, alias: String, cond: String) -> BaseDao:
	return left_join(__database, table, alias, cond, _PASSWORD)
	
## 联表查询，简化用户输入参数，使用用户数据文件夹作为数据库，使用用户数据文件的默认密码
func left_join_use_user_db_and_default_pass(table: String, alias: String, cond: String) -> BaseDao:
	return left_join("user://", table, alias, cond, PasswordDef.USER_DAO_PASS)
	
## 联表查询，简化用户输入参数，使用游戏配置文件夹作为数据库，使用游戏配置文件的默认密码
func left_join_use_conf_db_and_default_pass(table: String, alias: String, cond: String) -> BaseDao:
	return left_join("res://src/config/", table, alias, cond, PasswordDef.CONFIG_ENCRYPTED_PASS)
	
## 检查数组中的单个数据的结构是否都是一个键对应一个字典
func ___datas_struct_is_key_dict(datas: Array) -> bool:
	if datas.is_empty():
		return false
		
	# 检查第一个就行
	for k in datas[0]:
		if !(datas[0][k] is Dictionary):
			return false
	return true
	
func ___loop_table_row(result: Array, all_datas: Dictionary, loop_tables: Array, loop_index: int, 
curr_row: Dictionary):
	if loop_index == loop_tables.size():
		var ret = curr_row.duplicate()
		# 循环到头了，依次检查每个表是否满足on条件
		var arr_left_join = __left_join.get_chain_left_joins()
		for a_left_join in arr_left_join:
			var cond = a_left_join.get_condition()
			var conditionWrapper: ConditionWrapper = ConditionWrapper.new()
			if not conditionWrapper.cond(cond).check(curr_row):
				ret.erase(a_left_join.get_alias())
				
		# 多次检查依赖项是否存在，不存在需要删除
		for i in 10000:
			var delete_flag = false
			for a_left_join in arr_left_join:
				var dependencies: Array = a_left_join.get_dependencies()
				for t in dependencies:
					if t != __table_alias and !ret.has(t):
						ret.erase(t)
						delete_flag = true # 删除过就需要重新检查
						
			if delete_flag == false:
				break
				
		# 这条数据可用
		# 至少要包含两个表（因为ret必定包含主表，还需要再多包含一个别的表，那么长度就大于1了）
		if ret.size() > 1:
			result.push_back(ret)
			
	else:
		var table = loop_tables[loop_index]
		for row in all_datas[table]:
			var acc_row = curr_row.duplicate()
			acc_row[table] = row
			___loop_table_row(result, all_datas, loop_tables, loop_index + 1, acc_row)
	
func ___select(path: String, fill_primary_key: String = ""):
	var ret: Array = []
	var conf: ImprovedConfigFile = __CONF_MANAGER.get_conf(path, _PASSWORD)
	assert(_assert("___select", conf != null, "failed to get conf:%s" % path))
	conf.fill_primary_key = fill_primary_key
	var all_datas: Dictionary = {} # 把其他联表数据放到这个里边
	
	# 取主表所有数据
	all_datas[__table_alias] = conf.get_all_section_values()
	
	# 取联表所有数据
	var arr_left_join = __left_join.get_chain_left_joins() if __left_join != null else []
	for a_left_join in arr_left_join:
		var pt = a_left_join.get_path()
		var ps = a_left_join.get_password()
		var conf1: ImprovedConfigFile = __CONF_MANAGER.get_conf(pt, ps)
		conf1.fill_primary_key = fill_primary_key
		all_datas[a_left_join.get_alias()] = conf1.get_all_section_values()
		
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
			___loop_table_row(row_result, all_datas, loop_tables, 0, {__table_alias: row})
			# 这行主表的数据没有联到任何其他表的数据，因此需要一条别的表全为null的数据
			if row_result.is_empty():
				ret.push_back({__table_alias: row})
			else:
				ret.append_array(row_result)
				
	# 空数据并且不需要返回表头
	if ret.is_empty() and (__parent_union != null or not __need_head):
		return ret
		
	# 计算表头
	var real_select = []
	var regex_symbol = RegEx.new()
	regex_symbol.compile("[a-zA-Z_]+[0-9a-zA-Z]*")
	var regex_field = RegEx.new()
	var gen_dict = func(s, c, f, d = "", t = ""):
		return {"select_name": s, "Column Name": c, "is_field": f, "db_path": d, 
				"table_name": t, "Hint": "", "Hint String": ""}
	var fill_select_name = func(element, alias):
		element["select_name"] = element["Column Name"] if alias.is_empty() \
			else (alias + "." + element["Column Name"])
		return element
	for s in __select:
		if s == "*":
			for alias in all_datas:
				if alias == __table_alias:
					real_select.append_array(
						__get_table_columns(__database, __table, __table_alias, all_datas)\
						.map(fill_select_name.bind(alias)))
				else:
					var a_left_join = __left_join.get_left_join_by_alias(alias)
					real_select.append_array(
						__get_table_columns(a_left_join.get_db(), a_left_join.get_table(), alias, all_datas)\
						.map(fill_select_name.bind(alias)))
		elif s.ends_with(".*"):
			var alias = s.substr(0, s.length() - 2)
			if alias == __table_alias:
				real_select.append_array(
					__get_table_columns(__database, __table, __table_alias, all_datas)\
					.map(fill_select_name.bind(alias)))
			else:
				assert(_assert("___select", __left_join != null, "table `%s` not found" % alias))
				var a_left_join = __left_join.get_left_join_by_alias(alias)
				assert(_assert("___select", a_left_join != null, "table `%s` not found" % alias))
				real_select.append_array(
					__get_table_columns(a_left_join.get_db(), a_left_join.get_table(), alias, all_datas)\
						.map(fill_select_name.bind(alias)))
		else:
			var m = regex_symbol.search(s)
			if m != null and m.get_string() == s:
				assert(_assert("___select", __left_join == null, 
					"must specify table alias name in select fields if using left join"))
				var column = __get_table_column_defination(__database, __table, m.get_string())
				if column != null and !column.is_empty():
					column["is_field"] = true # 表示该字段是表本身就有的字段
					real_select.push_back(column)
				else:
					assert(_assert("___select", 
						not all_datas[__table_alias].is_empty() and all_datas[__table_alias][0].has(s),
						"field:[%s] not exist in table:[%s], db:[%s]" % [s, __table, __database]))
					real_select.push_back(gen_dict.call(s, s, true))
			elif s.contains(__table_alias + "."):
				regex_field.compile(__table_alias + "\\.([a-zA-Z_]+[0-9a-zA-Z]*)") # 获取字段名称的正则
				m = regex_field.search(s)
				if m:
					var field = m.get_string(1)
					var column = __get_table_column_defination(__database, __table, field)
					if column != null and !column.is_empty():
						if s == __table_alias + "." + field:
							column["is_field"] = true # 表示该字段是表本身就有的字段
						else:
							column["Column Name"] = s
							column["is_field"] = false
						column["select_name"] = s
						real_select.push_back(column)
					else:
						if s == __table_alias + "." + field:
							assert(_assert("___select", 
								not all_datas[__table_alias].is_empty() and all_datas[__table_alias][0].has(field),
								"field:[%s] not exist in table:[%s], db:[%s]" % [field, __table, __database]))
							real_select.push_back(gen_dict.call(s, field, true, __database, __table))
						else:
							real_select.push_back(gen_dict.call(s, s, false))
				else:
					# 不能100%确定有错误，所以不报错了
					real_select.push_back(gen_dict.call(s, s, false))
			else:
				var find = false
				for a_left_join in arr_left_join:
					var alias = a_left_join.get_alias()
					if s.contains(alias + "."):
						find = true
						regex_field.compile(alias + "\\.([a-zA-Z_]+[0-9a-zA-Z]*)") # 获取字段名称的正则
						m = regex_field.search(s)
						if m:
							var field = m.get_string(1)
							var column = __get_table_column_defination(
								a_left_join.get_db(), a_left_join.get_table(), field)
							if column != null and !column.is_empty():
								if s == alias + "." + field:
									column["is_field"] = true # 表示该字段是表本身就有的字段
								else:
									column["Column Name"] = s
									column["is_field"] = false
								column["select_name"] = s
								real_select.push_back(column)
							else:
								if s == alias + "." + field:
									assert(_assert("___select", 
										not all_datas[alias].is_empty() and all_datas[alias][0].has(field),
										"field:[%s] not exist in table:[%s], db:[%s]" \
										% [field, a_left_join.get_table(), a_left_join.get_db()]))
									real_select.push_back(
										gen_dict.call(s, field, true, a_left_join.get_db(), a_left_join.get_table()))
								else:
									real_select.push_back(gen_dict.call(s, s, false))
						break
						
				if not find:
					real_select.push_back(gen_dict.call(s, s, false))
		
	for f in real_select:
		if not f.has("select_name"):
			f["select_name"] = f["Column Name"]
			
		if __field_as.has(f["select_name"]):
			f["field_as"] = __field_as[f["select_name"]]
		else:
			f["field_as"] = f["Column Name"]
			
	if ret.is_empty():
		return [real_select]
		
	# where条件
	var cond = _get_cond(false)
		
	var ret_filter: Array[Dictionary] = []
	for data in ret:
		var conditionWrapper: ConditionWrapper = ConditionWrapper.new()
		if conditionWrapper.cond(cond).check(data):
			ret_filter.push_back(data)
			
	# 合并union
	if __union_all:
#		__union_all.__need_post_porcess = false # 改为需要后处理
#		__union_all.__need_head = false
		var union_datas = __union_all.___select(__union_all.__database + __union_all.__table)
		ret_filter.append_array(union_datas)
		# 防止内存占用
		__union_all.reset()
		
	# 特殊标记
	var __ROW_POST_PROCESS__ = "__ROW_POST_PROCESS_1355--5--__" # 祈祷用户没有用这个字段或表名
	
	# 排序
	if not __order_by.is_empty():
		var compare := func(a, b):
			for a_order_by in __order_by:
				var s = a_order_by[0].split(".")
				var t1 = s[0] if s.size() > 1 else ""
				var t2 = t1 # t1、t2分开是因为在union时，可能不同表有不同的别名
				var f = s[1] if s.size() > 1 else s[0]
				var d1 = a
				var d2 = b
				# 用户没有用t.xxx，而是用的xxx，这种情况，单表时，可以帮助用户识别表名
				if t1 == "" and a is Dictionary \
					and (a.size() == 1 or (a.size() == 2 and a.has(__ROW_POST_PROCESS__))):
					var ts: Array = a.keys()
					ts.erase(__ROW_POST_PROCESS__)
					t1 = ts[0]
				if t2 == "" and b is Dictionary \
					and (b.size() == 1 or (b.size() == 2 and b.has(__ROW_POST_PROCESS__))):
					var ts: Array = b.keys()
					ts.erase(__ROW_POST_PROCESS__)
					t2 = ts[0]
				if t1 != "" or (a is Dictionary and a.has("")):
					d1 = a.get(t1)
				if t2 != "" or (b is Dictionary and b.has("")):
					d2 = b.get(t2)
				if d1.get(f) == d2.get(f):
					continue
				else:
					if a_order_by[1] == ORDER_BY.ASC:
						return d1.get(f) < d2.get(f) # TODO 用evaluate的方式
					else:
						return d1.get(f) > d2.get(f)
						
			return true
			
		ret_filter.sort_custom(compare)
		
	# limit
	if __offset >= 0 and __limit > 0:
		ret_filter = ret_filter.slice(__offset, __limit)
		
	# 不用后处理，那么就返回所有字段，这基本就是update的时候内部调用select才使用。用户不应该到这里。
	if not __need_post_porcess:
		return ret_filter
		
	# 最终返回的数据：如果有parent_union，则仍旧返回按表分类的结构的数据，
	# 并多了一个字段（__ROW_POST_PROCESS__），是后处理数据的一行结果。
	# 如果没有parent_union，则返回扁平数组结构的数据。
	var ret_post_process: Array = []
	# 下面按照用户需要的字段及其顺序，返回相应的数据
	# 为了提升效率，简化一些常用查询。单表查询并查全字段
	if __left_join == null and __select.size() == 1 \
		and (__select[0] == "*" or __select[0] == __table_alias + ".*"):
		if __need_head and __parent_union == null:
			ret_post_process.push_back(real_select)
			
		for d in ret_filter:
			if d.has(__ROW_POST_PROCESS__):
				if __parent_union:
					ret_post_process.push_back(d)
				else:
					ret_post_process.push_back(d[__ROW_POST_PROCESS__])
				continue
				
			var row = []
			for f in real_select:
				row.push_back(d[__table_alias][f["Column Name"]])
			if __parent_union:
				d[__ROW_POST_PROCESS__] = row
				ret_post_process.push_back(d)
			else:
				ret_post_process.push_back(row)
	else:
		# 表头
		if __need_head and __parent_union == null:
			ret_post_process.push_back(real_select)
			
		# 数据格式是统一按表分类的，把字段中点号取值处理成方括号取值
		# 匹配t.name.substr(10)这种字符串。不匹配的会原样输出，不会被替换
		# 注意：这里不兼容t.name.a.b.substr(10)这种太多级的写法。会被改成t["name"].a["b"].substr(10)
		for i in real_select.size():
			# t.name.substr(10) 被替换为：t["name"].substr(10)
			real_select[i]["name_4_computing"] = ConditionWrapper.modify_dot_to_get(real_select[i]["select_name"])
				
		# 求值
		var is_single_table = ret_filter[0].size() == 1 or \
			(ret_filter[0].size() == 2 and ret_filter[0].has(__ROW_POST_PROCESS__)) # 每行数据是否只有一个表
			
		for data in ret_filter:
			if data.has(__ROW_POST_PROCESS__):
				if __parent_union:
					ret_post_process.push_back(data)
				else:
					ret_post_process.push_back(data[__ROW_POST_PROCESS__])
				continue
				
			var variable_names = []
			var variable_values = []
			# 把求式子可能需要的变量名称和变量值都放到数组里
			for key in data:
				variable_names.push_back(key)
				variable_values.push_back(data[key])
				# 还要考虑field不是用的t.xxx而是直接用的xxx的结构该怎么办
				# 联表时一般select的字段习惯上都会使用`别名.字段`这种形式，所以只考虑单表的情况
				# 单表查询，我们除了按dictionary传给variable_names，也按每个字段传给variable_names
				# 但是还是有缺点，就是字段名称和表别名重名了（概率小），另一个就是字段名称使用了Godot函数名称，
				# 导致函数名称被替换了（用户需要注意）
				if is_single_table:
					for f in data[key]:
						variable_names.push_back(f) # 祈祷字段名称和表名以及用户使用的函数名称不一样吧……
						variable_values.push_back(data[key][f])
				
			# 每行就是一个数组，按照用户select的顺序排列的，用户自己取。原来的想法是row是一个字典，
			# 但是存在一个值是由多个表里的数据或者并不是某个表里的数据计算出来的，不太好处理，放弃了。
			# 另外存在一个问题，就是星号怎么办。一个星号就代表了这个表所有的字段，用户很难知道返回的数据每个元素都对应哪个字段
			# 所以考虑返回数据的第一行是一个表头（用户可以传参数要不要这个表头）。
			# （这个考虑的结果最终决定了在上面的代码中增加了表头处理）
			var row = []
			# 按字段顺序挨个处理
			for field in real_select:
				# 如果field不是一个字段，比如是一个单纯的数字、字符串，在union的时候，会有问题，后续表会用首表的字段
				# 考虑union的时候，开启__need_post_porcess，并把最终结果放到某个特定的字段下，且仍旧返回按表分类的数据结构
				# 求值的时候增加一个判断分支，如果数据存在这个特定的字段，则不进行求值，而是直接使用已经求出的值
				# 直到第一个BaseDao，会返回扁平结构的数据
				var value = mgr.evaluate_command(null, field["name_4_computing"], variable_names, variable_values)
				row.push_back(value)
				
			if __parent_union:
				data[__ROW_POST_PROCESS__] = row
				ret_post_process.push_back(data)
			else:
				ret_post_process.push_back(row)
			
	return ret_post_process
	
func __get_table_defination(db_path: String, table_name: String):
	var columns: Array
	if Engine.has_singleton("GDSQLWorkbenchManager"):
		if mgr.databases:
			columns = mgr.get_table_columns(db_path, table_name)
		
	if columns == null or columns.is_empty():
		if __root_config == null:
			__root_config = ImprovedConfigFile.new()
			__root_config.load(ROOT_CONFIG_PATH)
		if __config == null:
			var db_info = __root_config.filter_first_values("data_path", db_path)
			if db_info.is_empty():
				return []
				
			var table_conf_path = db_info.get("config_path") + table_name.get_basename() + CONF_EXTENSION
			if not FileAccess.file_exists(table_conf_path):
				return []
				
			__config = ImprovedConfigFile.new()
			__config.load(table_conf_path)
			
		columns = __config.get_value(table_name.get_basename(), "columns", [])
		
	return columns
	
func __get_table_columns(db_path, table_name, table_alias, all_datas: Dictionary = {}):
	var columns: Array
	var defination = __get_table_defination(db_path, table_name)
	if defination:
		columns = defination
		
	if columns == null or columns.is_empty():
		# 推断表头
		assert(_assert("__get_table_columns", not all_datas.get(table_alias, []).is_empty(), 
			"db: [%s] table [%s] cannot get head: no defination of this table or any data of this table" \
			% [db_path, table_name]))
		columns = all_datas[table_alias][0].keys().map(func(v):
			return {"select_name": v, "Column Name": v, "is_field": true})
		
	if columns != null:
		columns = columns.duplicate(true)
		for i in columns:
			i["db_path"] = db_path
			i["table_name"] = table_name
			
	return columns
	
func __get_table_column_defination(db_path, table_name, column_name):
	var columns = __get_table_defination(db_path, table_name)
	var column
	if columns != null:
		for i in columns:
			if i["Column Name"] == column_name:
				column = i
				break
				
	if column != null:
		column = (column as Dictionary).duplicate(true)
		column["db_path"] = db_path
		column["table_name"] = table_name
		
	return column
	
## 执行。注意：在union的情况下，会自动执行第一个BaseDao的query方法。
func query():
	assert(_assert("query", !__database.is_empty(), "database is empty"))
	assert(_assert("query", !__table.is_empty(), "table is empty"))
	assert(_assert("query", !__cmd.is_empty(), "command is empty"))
	
	if __parent_union:
		return __parent_union.query()
		
	var path = __database + __table
	match __cmd:
		"select":
			var ret = ___select(path)
			reset()
			return ret
		"insert_into", "insert_ignore", "insert_or_update", "replace_into":
			assert(_assert("query:%s" % __cmd, !__data.is_empty(), "data is empty"))
			assert(_assert("query:%s" % __cmd, 
				__primary_key != null and __primary_key != "", "primary key is empty"))
			var ret = {
				"err": OK,
				"affected_rows": 0
			}
			# 检查数据类型是否正确
			var columns_def = __get_table_defination(__database, __table)
			for col in columns_def:
				var col_name = col["Column Name"]
				if __data.has(col_name):
					assert(_assert("query:%s" % __cmd, typeof(__data[col_name]) == col["Data Type"], 
						"data type of %s is not %s" % \
						[col_name, DataTypeDef.DATA_TYPE_NAMES[typeof(__data[col_name])]]))
						
			var conf: ImprovedConfigFile = __CONF_MANAGER.get_conf(path, _PASSWORD)
			assert(_assert("query:%s" % __cmd, conf != null, "load conf err!"))
			var primary_value = str(__data.get(__primary_key))
			var insert = true # 是insert模式还是update模式。只有insert_or_update时会涉及
			if primary_value == null:
				# 这几种插入操作都需要主键存在，用户要不就直接在data里写好了主键，要不就设置为自增，否则报错
				if __autoincrement_keys.has(__primary_key) or __autoincrement_keys_def.has(__primary_key):
					pass # 后面会统一把所有需要自增的键一起处理
				else:
					ret["err"] = "key 'PRIMARY' is missing for %s" % __cmd
					push_error(ret["err"])
					return ret
			else:
				if conf.has_section(primary_value):
					if __cmd == "insert_ignore":
						# 数据存在，不用插入
						return ret
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
						conf.erase_section(primary_value)
						ret["affected_rows"] += 1
					else:
						ret["err"] = "Duplicate entry '%s' for key 'PRIMARY'" % primary_value
						push_error(ret["err"])
						return ret
						
			# 自增:找到当前最大的
			var datas: Array[Dictionary] = conf.get_all_section_values()
			var autoincrement_keys = __autoincrement_keys.duplicate()
			autoincrement_keys.merge(__autoincrement_keys_def) # 合并字典，不要重复计算
			for field in autoincrement_keys:
				if __data.get(field) == null or __data.get(field) == 0:
					for data in datas:
						if data.get(field) != null and data.get(field) >= autoincrement_keys.get(field):
							autoincrement_keys[field] = data.get(field)
							
			for field in autoincrement_keys:
				if __data.get(field) == null or __data.get(field) == 0:
					__data[field] = autoincrement_keys.get(field) + 1
					
			# insert模式下，对于有表结构定义的数据，每个字段都必须插入，也不能有多余的字段。需在自增之后检查。
			if insert and not columns_def.is_empty():
				var col_names = []
				for col in columns_def:
					var col_name = col["Column Name"]
					col_names.push_back(col_name)
					if __data.has(col_name):
						continue
						
					if not col["Default(Expression)"].is_empty():
						__data[col_name] = mgr.evaluate_command(null, col["Default(Expression)"])
						continue
						
					if col["NN"]:
						ret["affected_rows"] = 0
						ret["err"] = "field '%s' needs to be set" % col_name
						push_error(ret["err"])
						return ret
					else:
						__data[col_name] = null
						
				if __data.size() != columns_def.size():
					ret["affected_rows"] = 0
					ret["err"] = "invalid field(s): %s" % ",".join(
						__data.keys().filter(func(v): return not col_names.find(v)))
					push_error(ret["err"])
					return ret
					
			# 检查唯一性：只关注新插入的数据是否与旧数据重复
			for col in columns_def:
				if not col["UQ"]:
					continue
				var col_name = col["Column Name"] 
				for data in datas:
					if __data[col_name] == data.get(col_name, null):
						ret["affected_rows"] = 0
						ret["err"] = "Duplicate field value '%s' for key '%s'" % \
							[var_to_str(__data[col_name]), col_name]
						push_error(ret["err"])
						return ret
						
			# 插入
			conf.set_values(str(__data.get(__primary_key)), __data)
			if __auto_commit:
				__CONF_MANAGER.save_conf_by_origin_password(path)
			ret["affected_rows"] += 1
			ret["last_insert_id"] = __data.get(__primary_key)
			reset()
			return ret
			
		"update":
			assert(_assert("query:%s" % __cmd, !__data.is_empty(), "data is empty"))
			assert(_assert("query:%s" % __cmd, !__where.is_empty(), "where is empty"))
			var ret = {
				"err": OK,
				"affected_rows": 0
			}
			
			# 检查数据类型是否正确
			var columns_def = __get_table_defination(__database, __table)
			for col in columns_def:
				var col_name = col["Column Name"]
				if __data.has(col_name):
					assert(_assert("query:%s" % __cmd, typeof(__data[col_name]) == col["Data Type"], 
						"data type of field `%s` is not %s" % [col_name, DataTypeDef.DATA_TYPE_NAMES[typeof(__data[col_name])]]))
						
			# 筛选出要更新的数据
			var primary = "__PRIMARY_1355--5--__" # 让数据库把主键存到这个键里，祈祷用户没有用到这个字段
			__need_post_porcess = false # update一定是单表，用内部返回模式返回数据
			var datas = ___select(path, primary)
			if datas.is_empty():
				return ret
			
			# 更新数据
			var conf: ImprovedConfigFile = __CONF_MANAGER.get_conf(path, _PASSWORD)
			assert(_assert("query:%s" % __cmd, conf != null, "load conf err!"))
			var affected_rows = 0
			for data in datas:
				data = data[__table_alias] # 未经过后处理的肯定是用表名分类的结构
				var affected = false
				for field in __data:
					if conf.get_value(str(data.get(primary)), field) != __data.get(field):
						conf.set_value(str(data.get(primary)), field, __data.get(field))
						affected = true
				if affected:
					affected_rows += 1
					
			if __auto_commit and affected_rows > 0:
				__CONF_MANAGER.save_conf_by_origin_password(path)
			ret["affected_rows"] = affected_rows
			reset()
			return ret
			
func _get_cond(need_where: bool, new_line = false) -> String:
	var cond = ""
	for i in __where:
		if cond != "":
			cond += " and "
		cond += "(" + i + ")"
	
	if cond.is_empty():
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
		arr.push_back("%s %s" % [i[0], "asc" if i[1] == ORDER_BY.ASC else "desc"])
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
	
## 获取正正执行的语句
func get_query_cmd() -> String:
	var a_table = __table.substr(0, __table.length() - DATA_EXTENSION.length())
	match __cmd:
		"select":
			return "select %s from %s%s%s%s%s%s%s" % [
				", ".join(__select.map(func(v): return (v + " as " + __field_as[v]) if __field_as.has(v) else v)), 
				a_table,
				"" if __table_alias.is_empty() else " " + __table_alias,
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
	
			
func reset(force = false):
	if force == false and Engine.is_editor_hint():
		return
	__select = []
	__table = ""
	__cmd = ""
	__table_alias = ""
	__data = {}
	__where = []
	__order_by = []
	__offset = -1
	__limit = -1
	__duplicate_update_fields = []
	__primary_key = ""
	__primary_key_def = ""
	__autoincrement_keys = {}
	__autoincrement_keys_def = {}
	__union_all = null
	__parent_union = null
	if __left_join:
		__left_join.clear_chain()
		__left_join = null
	__CONF_MANAGER = null
	if __config:
		__config.clear()
		__config = null
	if __root_config:
		__root_config.clear()
		__root_config = null
