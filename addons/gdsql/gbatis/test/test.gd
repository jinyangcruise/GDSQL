extends Node2D

@export var skill_mapper: TestSkillMapper

func _ready() -> void:
	await get_tree().create_timer(3).timeout
	#var a = skill_mapper.select_skill_by_id(1)
	var b = skill_mapper.select_skill_by_id2(1)
	b = skill_mapper.select_skill_by_id2(1)
	b = skill_mapper.select_skill_by_id2(1)
	b = skill_mapper.select_skill_by_id2(1)
	#var list = skill_mapper.select_skill_list()
	pass
