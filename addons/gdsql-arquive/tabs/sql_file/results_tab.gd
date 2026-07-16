@tool
extends TabContainer

@export var v_split_container: VSplitContainer

var _tab_activate_time: float = 0
var _tab_history: Array


func _switch_to_previous_page(current_page: Node):
	for i in range(_tab_history.size() - 1, -1, -1):
		if _tab_history[i] == current_page:
			continue
		current_tab = get_tab_idx_from_control(_tab_history[i])
		break


func _on_tab_changed(tab: int) -> void:
	if tab < 0:
		return

	var tab_control = get_tab_control(tab)
	if _tab_history.has(tab_control):
		_tab_history.erase(tab_control)
		_tab_history.push_back(tab_control)

	_tab_activate_time = Time.get_unix_time_from_system()
	set_tab_button_icon(tab, get_theme_icon("Close", "EditorIcons"))
	for i in get_tab_count():
		if i != tab:
			set_tab_button_icon(i, null)


func _on_tab_button_pressed(tab: int) -> void:
	if tab != current_tab:
		current_tab = tab
		return

	if Time.get_unix_time_from_system() - _tab_activate_time < 0.5:
		return

	_close_tab(tab)


func _close_tab(tab_idx: int):
	if tab_idx < 0 or tab_idx >= get_tab_count():
		return

	var child = get_tab_control(tab_idx)
	_switch_to_previous_page(child)
	remove_child(child)
	child.queue_free()


func _on_child_exiting_tree(node: Node) -> void:
	if node in _tab_history:
		_tab_history.erase(node)
	if get_tab_count() == 1: # exiting 的时候，tab count 还不等于0
		hide()
