extends Node2D

@export var skill_mapper: TestSkillMapper

var d = []
func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	#var a = skill_mapper.select_skill_by_id(1)
	var t1 = Time.get_ticks_msec()
	for i in 1000:
		var c = skill_mapper.select_skill_by_id3(1)
		#d.push_back(var_to_bytes_with_objects(c))
		#d.push_back(var_to_str(c))
		pass
		#var b = skill_mapper.select_skill_by_id2(1)
	#for i in 100:
		#var e = bytes_to_var_with_objects(d[i])
		#var e = str_to_var(d[i])
		#printt(e.icon)
		#printt(i, e)
		#pass
	var t2 = Time.get_ticks_msec()
	printt(t2-t1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#var list = skill_mapper.select_skill_list()
	#var dao = SQLParser.parse_to_dao("select * from GameConfig.c_skill
		#where id == 1")
	pass
