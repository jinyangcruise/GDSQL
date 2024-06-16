extends Node2D

@export var skill_mapper: TestSkillMapper

var d = []
func _ready() -> void:
	#await get_tree().create_timer(0.5).timeout
	# test select 1
	var a = skill_mapper.select_skill_by_id(66)
	pass
	#var tree = Tree.new()
	#var root = tree.create_item()
	#var obj1 = tree.create_item(root)
	#var obj2 = tree.create_item(root)
	#var obj3 = tree.create_item(root)
	#var history = [obj1, obj2, obj3]
	#history.erase(obj3)
	#printt(history.has(obj3))
	#pass
	
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
	
	# test select 2
	#var b = skill_mapper.select_skill_by_id2(66)
	#pass
	#b = skill_mapper.select_skill_by_id2(1)
	#b = skill_mapper.select_skill_by_id2(1)
	
	# test select 3
	#var list = skill_mapper.select_skill_list()
	#var dao = SQLParser.parse_to_dao("select * from GameConfig.c_skill
		#where id == 1")
		
	# test update
	#var entity = TestSkillEntity.new()
	#entity.id = 65
	#entity.skill_name = "rjweor"
	#entity.desc = "32423"
	#entity.icon = load("res://src/new_game/img/ok.png")
	#var u = skill_mapper.update_skill(entity)
	#printt(u)
	
	# test insert
	#var entity2 = TestSkillEntity.new()
	##entity2.id = 6
	#entity2.skill_name = "新的技能xxx"
	#entity2.desc = "flkjfasl加入了认为"
	#entity2.icon = load("res://addons/anthonyec.camera_preview/GuiResizerTopLeft.svg")
	#var v = skill_mapper.insert_skill(entity2)
	#printt(v, entity2.id)
	
	# test insert 2
	#var entity3 = TestSkillEntity.new()
	#entity3.id = 66
	#entity3.skill_name = "skill66"
	#entity3.icon = load("res://addons/gdsql/img/plusfile.png")
	#var v3 = skill_mapper.insert_skill2(entity3)
	#printt(v3)
	
	# test insert 3 by Dictionary
	#var map = {
		#"id": 66,
		#"skill_name": "66_skill",
		#"icon": load("res://src/hero/img/ap.png"),
		#"desc": "a desc",
		#"max_level": 99,
		#"xxx": 9923,
		#"xxxww": 555,
	#}
	#var v4 = skill_mapper.insert_skill3(map)
	#printt(v4)
	
	# test insert 4
	#var map = {
		#"id": 67,
		#"skill_name": "67_skill",
		#"icon": load("res://src/hero/img/mp.png"),
		#"desc": "a desc xxx",
		#"max_level": 2,
	#}
	#var v5 = skill_mapper.insert_skill4(map)
	#printt(v5)
	
	# test replace 
	#var entity4 = TestSkillEntity.new()
	#entity4.id = 64
	#entity4.skill_name = "thisskill64"
	#entity4.icon = load("res://src/hero/img/hp.png")
	#entity4.max_level = 5
	#var v6 = skill_mapper.replace_skill(entity4)
	#printt(v6)
	
	# test delete 1
	#var v7 = skill_mapper.delete_skill_by_id(67)
	#printt(v7)
	#var v8 = skill_mapper.select_skill_by_id(67)
	#printt(v8)
	
	# test delete 2
	#var v9 = skill_mapper.delete_skill_by_ids([63, 65])
	#printt(v9)
	pass

