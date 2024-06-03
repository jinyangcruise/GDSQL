extends Node2D

@export var skill_mapper: TestSkillMapper

var d = []
func _ready() -> void:
	#await get_tree().create_timer(0.5).timeout
	#var a = skill_mapper.select_skill_by_id(1)
	#var t1 = Time.get_ticks_msec()
	#for i in 1000:
		#var c = skill_mapper.select_skill_by_id3(1)
		##d.push_back(var_to_bytes_with_objects(c))
		##d.push_back(var_to_str(c))
		#pass
		##var b = skill_mapper.select_skill_by_id2(1)
	##for i in 100:
		##var e = bytes_to_var_with_objects(d[i])
		##var e = str_to_var(d[i])
		##printt(e.icon)
		##printt(i, e)
		##pass
	#var t2 = Time.get_ticks_msec()
	#printt(t2-t1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	#var list = skill_mapper.select_skill_list()
	#var dao = SQLParser.parse_to_dao("select * from GameConfig.c_skill
		#where id == 1")
	#var entity = TestSkillEntity.new()
	#entity.id = 63
	#entity.skill_name = "2131测试名字"
	#entity.desc = "423测试描述。。。。。。。。。。。。。。"
	#var u = skill_mapper.update_skill(entity)
	#printt(u)
	
	#var s = "insert into c_skill( name, desc )values( ___Rep1___, ___Rep0___ )"
	#var regex = RegEx.new()
	#regex.compile(r"(?is)(INSERT(?:\s+IGNORE)?\s+INTO)\s+([^\s(]+(\s*\([^)]*\))?)\s*(VALUES)\s*(\([^)]*\))(\s*ON DUPLICATE KEY UPDATE)?(\s*.*)?")
	#var m = regex.search(s)
	var ss = "1"
	var sss = str_to_var(ss)
	printt(sss)
	var entity2 = TestSkillEntity.new()
	#entity2.id = 6
	entity2.skill_name = "新的技能xxx"
	entity2.desc = "flkjfasl加入了认为"
	entity2.icon = load("res://addons/anthonyec.camera_preview/GuiResizerTopLeft.svg")
	var v = skill_mapper.insert_skill(entity2)
	printt(v, entity2.id)
	pass

