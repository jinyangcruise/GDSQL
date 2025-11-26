@tool
extends RefCounted

var __request_password: Array
var __database: String = "" ## 【外部请勿使用】数据库路径
var __password: String = "" ## 数据表密码
var __table: String = "" ## 【外部请勿使用】表名
var __table_alias: String = "" ## 【外部请勿使用】别名
var __condition: String = "" ## 【外部请勿使用】联表查询条件
#var __dependencies: Array = [] ## 依赖的表
var __left_join: GDSQL.LeftJoin  ## 【外部请勿使用】后续的联表对象（单纯的前后顺序关系，与__condition无关）

#static var regex = RegEx.new()

#static func _static_init() -> void:
	#regex.compile("(\\b[0-9a-zA-Z_]+\\b)\\.[0-9a-zA-Z_\\-]+")
	
func set_db(database: String):
	__database = database
	
func get_db() -> String:
	return __database
	
func set_password(password: String):
	__password = password
	
func get_password() -> String:
	return __password
	
func set_table(table: String):
	__table = table
	
func get_table() -> String:
	return __table
	
func get_path() -> String:
	return __database.path_join(__table)
	
func set_alias(alias: String):
	__table_alias = alias
	
func get_alias() -> String:
	return __table_alias
	
func set_condition(cond: String):
	__condition = cond
	
func get_condition() -> String:
	return __condition
	
#func set_dependencies(dependencies: Array):
	#__dependencies = dependencies
	
#func get_dependencies() -> Dictionary:
	#var dependencies = [] # 依赖的表
	#var matchs = regex.search_all(__condition)
	#for i in matchs:
		#var t = i.get_string(1)
		#if t != __table_alias and !dependencies.has(t):
			#dependencies.push_back(t)
	#return {__table_alias: dependencies}
	
func set_left_join(left_join: GDSQL.LeftJoin):
	__left_join = left_join
	
func remove_left_join(left_join: GDSQL.LeftJoin) -> bool:
	if __left_join == left_join:
		__left_join = null
		return true
	return false
	
func get_left_join() -> GDSQL.LeftJoin:
	return __left_join
	
## 检查链条上是否有该别名的联表对象
func chain_has_alias(alias: String) -> bool:
	if __table_alias == alias:
		return true
		
	var obj = __left_join
	while obj != null:
		if obj.__table_alias == alias:
			return true
		obj = obj.__left_join
		
	return false
	
## 在链条末尾增加一个LeftJoin对象
func create_left_join_to_end(a_left_join: GDSQL.LeftJoin = null):
	if __left_join == null:
		__left_join = GDSQL.LeftJoin.new() if a_left_join == null else a_left_join
		return __left_join
		
	var obj = __left_join
	while obj.__left_join != null:
		obj = obj.__left_join
		
	obj.__left_join = GDSQL.LeftJoin.new() if a_left_join == null else a_left_join
	return obj.__left_join
	
## 获取链条上的LeftJoin对象。注意需要在根对象上调用。
func get_chain_left_joins() -> Array[GDSQL.LeftJoin]:
	var ret: Array[GDSQL.LeftJoin] = [self]
	var obj = __left_join
	while obj != null:
		ret.push_back(obj)
		obj = obj.__left_join
	return ret
	
## 根据别名获取链条上LeftJoin对象。注意需要在根对象上调用。
func get_left_join_by_alias(alias) -> GDSQL.LeftJoin:
	if __table_alias == alias:
		return self
	var obj = __left_join
	while obj != null:
		if obj.get_alias() == alias:
			return obj
		obj = obj.__left_join
	return null
	
func clear_chain():
	var arr = [self]
	var obj = __left_join
	while obj != null:
		arr.push_back(obj)
		obj = obj.__left_join
	for i in arr:
		i.__left_join = null
		
func get_query_cmds() -> Array:
	var ret = ["left join %s %s on %s" % [__table, __table_alias, __condition]]
	var obj = __left_join
	while obj != null:
		ret.push_back("left join %s %s on %s" % [obj.__table, obj.__table_alias, obj.__condition])
		obj = obj.__left_join
	return ret
	
## 只有在编辑器模式时才可能返回true
func need_user_enter_password() -> bool:
	return not __request_password.is_empty()
	
## mgr: GDSQLWorkbenchManager
func handle_defualt_password(mgr):
	__request_password.clear()
	# 在编辑器模式，要求用户输入密码
	if mgr and Engine.is_editor_hint():
		if mgr.need_request_password(get_db(), get_table(), get_password()):
			__request_password.push_back(true)
			return
	elif __password == "":
		if __database == "user://":
			__password = GDSQL.PasswordDef.USER_DAO_PASS
		elif __database == "res://src/config/":
			__password = GDSQL.PasswordDef.CONFIG_ENCRYPTED_PASS
