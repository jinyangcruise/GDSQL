extends Node
class_name GDSQLWorkbenchManagerClass

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

func create_confirmation_dialog(requester:Node, msg: String, confirmed_callback: Callable = Callable(), canceled_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = msg
	if confirmed_callback.is_valid():
		dialog.confirmed.connect(confirmed_callback)
	if canceled_callback.is_valid():
		dialog.canceled.connect(canceled_callback)
	requester.get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		if canceled_callback.is_valid():
			dialog.canceled.connect(canceled_callback)
		dialog.queue_free()
	)
	
func create_accept_dialog(requester:Node, msg: String):
	var dialog := AcceptDialog.new()
	dialog.dialog_text = msg
	requester.get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
	
