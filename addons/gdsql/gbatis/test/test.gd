extends Node2D

@export var skill_mapper: TestSkillMapper

func _ready() -> void:
	#await get_tree().create_timer(3).timeout
	#var a = skill_mapper.select_skill_by_id(1)
	var t1 = Time.get_ticks_msec()
	for i in 10:
		var c = skill_mapper.select_skill_by_id3(1)
		#var b = skill_mapper.select_skill_by_id2(1)
	var t2 = Time.get_ticks_msec()
	printt(t2-t1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#var list = skill_mapper.select_skill_list()
	#var dao = SQLParser.parse_to_dao("select * from GameConfig.c_skill
		#where id == 1")
