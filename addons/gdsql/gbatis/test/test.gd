extends Node2D

@export var skill_mapper: TestSkillMapper

var pos: Vector2

var re: Vector2

func _ready() -> void:
	var a = skill_mapper.select_skill_by_id(1)
	pass
