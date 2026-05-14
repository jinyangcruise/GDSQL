@tool
extends Node2D

var _suites = []
var _idx = 0

func _ready() -> void:
	print("")
	print("============================================================")
	print("  GDSQL Test Runner")
	print("============================================================")
	print("")
	print("Press SPACE to run all tests.")
	print("")

func _input(e) -> void:
	if e is InputEventKey and e.keycode == KEY_SPACE and e.pressed:
		_run()

func _run() -> void:
	_suites = [
		"res://test/sql_parser/test_sql_parser.tscn",
		"res://test/base_dao/test_base_dao.tscn",
		"res://test/expression/test_expression.tscn",
		"res://test/gbatis/test_gbatis.tscn"
	]
	_idx = 0
	_next()

func _next() -> void:
	if _idx >= _suites.size():
		print("")
		print("All test suites completed!")
		print("")
		return
	var p = _suites[_idx]
	print(">>> Loading: " + p)
	var old = get_node_or_null("_ts")
	if old:
		old.queue_free()
	var s = load(p)
	if s == null:
		printerr("  FAIL: load " + p)
		_idx += 1
		_next()
		return
	var n = s.instantiate()
	n.name = "_ts"
	add_child(n)
	_idx += 1
	await get_tree().process_frame
	await get_tree().process_frame
	if n:
		n.queue_free()
	_next()
