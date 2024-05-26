extends Node2D

@export var skill_mapper: TestSkillMapper

var pos: Vector2

var re: Vector2

func _ready() -> void:
	#var a = skill_mapper.select_skill_by_id(1) as QueryResult
	#Utils.print_variant(a.get_raw())
	#Utils.print_variant(get_method_list().filter(func(v): return v.name.begins_with("test")))
	#printt("pos" in self, "x" in self.pos)
	#var old = get_indexed("pos:x")
	#set_indexed("pos:x", type_convert('1', typeof(old)))
	#printt(pos)
	#set_indexed("re", type_convert("(1, 1)", TYPE_VECTOR2))
	#printt(re, var_to_str(Vector2.ONE), str_to_var("(1, 1)"))
	var a = "a".to_camel_case()
	printt(a[0].to_upper() + a.substr(10))
	
func test() -> Skill:
	return null
	
func test2() -> Array[Skill]:
	return []

func test3() -> Dictionary:
	return {}
	
func test4():
	pass
	
func test5() -> Variant:
	return 1
	
func test6() -> Array[int]:
	return []
