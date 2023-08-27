extends Node
class_name GDSQLWorkbenchManagerClass

## 属性检查器
var editor_interface: EditorInterface

## 数据库配置
#databases = {
	#"db1": {
		#"name": conf.get_value(db_name, "name"),
		#"path": conf.get_value(db_name, "path"),
		#"table_items": {
			#"table1": {
				#"table_name": "",
				#"file_name": "",
				#"path": ""
				#"columns": { # 可能为空
					#"col1": {
						#"AI": false,
						#"Column Name": "col1",
						#"Comment": "",
						#"Data Type": 4,
						#"Default(Expression)": "",
						#"Hint": 0,
						#"Hint String": "",
						#"NN": true,
						#"PK": false,
						#"UQ": false
					#}
				#}
			#}
		#},
		#"persistent": conf == _config_file, # 是否是持久化的
	#}
#}
var databases: Dictionary

func inspect_object(obj):
	editor_interface.inspect_object(obj, "", false)

func get_table_columns(db, table) -> Dictionary:
	if databases:
		return databases.get(db, {}).get("table_items", {}).get(table, {})\
			.get("columns", {})
	return {}
