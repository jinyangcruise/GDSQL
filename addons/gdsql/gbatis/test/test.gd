extends Node2D

@export var skill_mapper: TestSkillMapper

func _ready() -> void:
	var a = skill_mapper.select_skill_by_id(1) as QueryResult
	Utils.print_variant(a.get_raw())
