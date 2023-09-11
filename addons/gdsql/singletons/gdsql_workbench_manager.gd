extends Node
class_name GDSQLWorkbenchManagerClass

## 打开新建数据库标签页的信号
signal open_add_schema_tab
## 用户确认新建数据库的信号
signal user_confirm_add_schema(db_name: String, path: String, save: bool, id: String)
## 系统确认新建数据库的信号
signal sys_confirm_add_schema(id: String)

## 打开修改数据库标签页的信号
signal open_alter_schema_tab(db_name: String, path: String, save: bool)
## 用户确认修改数据库的信号
signal user_confirm_alter_schema(old_db_name: String, new_db_name: String, path: String, save: bool, id: String)
## 系统确认修改数据库的信号
signal sys_confirm_alter_schema(id: String)

## 打开新建数据表标签页的信号
signal open_add_table_tab(db_name: String)
## 用户确认新建表的信号
signal user_confirm_add_table(sechema: String, table_name: String, comments: String, 
	password: String, columns: Array, id: String)
## 系统确认新建数据表的信号
signal sys_confirm_add_table(id: String)

## 打开修改数据表标签页的信号
signal open_alter_table_tab(db_name: String, table_name: String)
## 用户确认修改数据表的信号
signal user_confirm_alter_table(sechema: String, old_table_name: String, new_table_name: String, 
	comments: String, password: String, columns: Array, id: String)
## 系统确认修改数据表的信号
signal sys_confirm_alter_table(id: String)

## 发送到编辑器
signal send_to_editor(content: String)
## 发送到编辑器并执行的信号
signal send_to_editor_and_execute(title: String, info: Dictionary)

## 记录操作日志
signal add_log_history(status: String, begin_timestamp: String, action: String, message: String)

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
				#"columns": [ # 可能为空
					#{
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
				#]
			#}
		#},
		#"persistent": conf == _config_file, # 是否是持久化的
	#}
#}
var databases: Dictionary

func get_table_columns(db, table) -> Array:
	if databases:
		return databases.get(db, {}).get("table_items", {}).get(table, {})\
			.get("columns", [])
	return []

func create_confirmation_dialog(msg: String, confirmed_callback: Callable = Callable(), canceled_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = msg
	if confirmed_callback.is_valid():
		dialog.confirmed.connect(confirmed_callback)
	if canceled_callback.is_valid():
		dialog.canceled.connect(canceled_callback)
	EditorInterface.get_base_control().get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		if canceled_callback.is_valid():
			dialog.canceled.connect(canceled_callback)
		dialog.queue_free()
	)
	
func create_accept_dialog(msg: String):
	var dialog := AcceptDialog.new()
	dialog.dialog_text = msg
	EditorInterface.get_base_control().get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
	
