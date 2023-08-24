extends Node
class_name GDSQLWorkbenchManagerClass

## 属性检查器
var editor_interface: EditorInterface

## 数据库配置
#databases.push_back({
	#"name": conf.get_value(db_name, "name"),
	#"path": conf.get_value(db_name, "path"),
	#"table_items": [
		#{
			#"table_name": "",
			#"file_name": "",
			#"path": ""
		#}
	#],
	#"persistent": conf == _config_file, # 是否是持久化的
#}
var databases: Array[Dictionary]

func inspect_object(obj):
	editor_interface.inspect_object(obj, "", false)
