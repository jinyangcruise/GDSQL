extends Node2D

func _ready() -> void:
	#test_update()
	#test_select2()
	#test_insert_db_config()
	test_left_join()

func test_insert():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.insert_into("t_user_2.gsql")\
		.primary_key("id", true)\
		.values({
			"name": "superman 1",
			"level": "999",
			"sex": 1
		})\
		.query()
	printt(ret)
		
func test_insert_ignore():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.insert_ignore("t_user_1.gsql")\
		.primary_key("id", true)\
		.values({
			"id": 1,
			"name": "bat man22222",
			"level": "a",
			"sex": 1
		})\
		.query()
	printt(ret)
		
func test_insert_or_update():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.insert_or_update("t_user_1.gsql")\
		.primary_key("id", true)\
		.values({
			"id": 1,
			"name": "bat man66",
			"level": "bb",
			"sex": 0
		})\
		.on_duplicate_update(["name", "level", "sex"])\
		.query()
	printt(ret)
		
func test_replace_into():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.replace_into("t_user_1.gsql")\
		.primary_key("id", true)\
		.values({
			"id": 1,
			"name": "bat man6697777",
			"level": "1222",
			"sex": 1
		})\
		.query()
	printt(ret)
		
func test_update():
	var dao: BaseDao = BaseDao.new()
	dao.set_password("")
	var ret = dao.update("t_user_2.gsql")\
		.primary_key("id", true)\
		.sets({
			"level": 998,
			"sex": 0
		})\
		.where("id > 30")\
		.query()
	printt(ret)
	
func test_select():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.select("id, name, level, sex", true)\
		.from("t_user_1.gsql")\
		.where("name.begins_with('bat')")\
		.query()
	printt(ret)
	
func test_select2():
	var dao: BaseDao = BaseDao.new()
	var ret = dao.use_user_db()\
		.set_password("")\
		.select("*", true)\
		.from("t_user_2.gsql")\
		.order_by("id", BaseDao.ORDER_BY.DESC)\
		.query()
	printt(ret)
	
func test_select_limit():
	var dao: BaseDao = BaseDao.new()
	dao._PASSWORD = ""
	var ret = dao.select("id*10 as a, name, level, sex", true)\
		.from("t_user_1.gsql", "t")\
		.where("t.name.contains('man')")\
		.order_by("t.id", BaseDao.ORDER_BY.DESC)\
		.limit(0, 2)\
		.query()
	printt(ret)
	
func test_union():
	var dao: BaseDao = BaseDao.new()
	var ret = dao.set_password("")\
		.select("id*10 as a, name, level, sex, 'user1'", true)\
		.from("t_user_1.gsql", "t")\
		.where("name.contains('man')")\
		.order_by("id", BaseDao.ORDER_BY.DESC)\
		.limit(0, 50)\
		
		.union_all()\
		.set_password("")\
#		.select("id*10 as a, name, level, sex, 'user2'", false)\
		.select_same()\
		.from("t_user_2.gsql", "")\
		.order_by("name", BaseDao.ORDER_BY.ASC)\
		.limit(0, 2)\
		
		.query()
		
	print(ret.size())
	printt(ret)
	
func test_left_join():
	var dao: BaseDao = BaseDao.new()
	var ret = dao.set_password("")\
		.select("t1.id, t1.name, t1.level, t1.sex, t2.id, t2.name, t2.level, t2.sex, 1+1 as a", true)\
		.from("t_user_2.gsql", "t2")\
		.left_join("", "t_user_1.gsql", "t1", "t2.id == t1.id", "")\
		.query()
		
	printt(ret)

func test_insert_into_complex_node():
	var dao: BaseDao = BaseDao.new()
	var main = preload("res://src/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ret = dao.replace_into("t_scene.gsql")\
		.primary_key("id", true)\
		.values({
			"id": 1,
			"data": main,
		})\
		.query()
	printt(ret)
	
func test_insert_db_config():
	var dao: BaseDao = BaseDao.new()
	return dao.use_db("res://addons/gdsql/config/")\
				.insert_into("config.cfg")\
				.primary_key("name", false)\
				.values({
					"name": "Game Config",
					"path": "res://src/config/",
				})\
				.query()
