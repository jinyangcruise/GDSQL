@tool
extends TabContainer

@onready var new_tab_button: Control = $"➕"

var _tab_index = 1

func _ready() -> void:
	pass


func _on_tab_clicked(tab: int) -> void:
	# 点击了“新建SQL页面”（加号），增加一个编辑页面，并激活
	if get_child(tab) == new_tab_button:
		var sql_file = preload("res://addons/gdsql/sql_file.tscn").instantiate()
		add_child(sql_file)
		move_child(new_tab_button, get_child_count())
		current_tab = get_child_count() - 2
		set_tab_title(current_tab, "SQL File %d" % _tab_index)
		_tab_index += 1
		
func _on_tab_button_pressed(tab: int) -> void:
	remove_child(get_tab_control(tab))
	# TODO 有内容的时候要提示保存或者二次确认

## 切换标签的时候，把激活的标签上加一个关闭按钮，没激活的标签取消关闭按钮防止误触
func _on_tab_changed(tab: int) -> void:
	if get_tab_control(tab) != new_tab_button:
		set_tab_button_icon(tab, preload("res://addons/gdsql/img/xmark.png"))
		
		for i in get_tab_count():
			if i != tab:
				set_tab_button_icon(i, null)
