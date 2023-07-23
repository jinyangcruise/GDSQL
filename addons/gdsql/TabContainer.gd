extends TabContainer

@onready var new_tab_button: Control = $aa


func _ready() -> void:
	pass


func _on_tab_clicked(tab: int) -> void:
	printt(111111)
	if get_child(tab) == new_tab_button:
		var sql_file = preload("res://addons/gdsql/sql_file.tscn").instantiate()
		add_child(sql_file)
		move_child(new_tab_button, get_child_count())
