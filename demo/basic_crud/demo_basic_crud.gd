@tool
extends Node2D

var _db_path = "user://demo_basic_crud_db/"

func _ready() -> void:
	print("")
	print("============================================================")
	print("  Demo: Basic CRUD - Ready!")
	print("============================================================")
	print("")
	print("Press SPACE to run all CRUD operations.")
	print("")

func _input(event) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		_run_all()

func _run_all() -> void:
	print("")
	print("============================================================")
	print("  Demo: Basic CRUD with GDSQL")
	print("============================================================")
	_setup_database()
	_create_hero_table()
	_insert_heroes()
	_select_heroes()
	_select_heroes_with_condition()
	_update_hero()
	_verify_update()
	_delete_hero()
	_verify_deletion()
	print("")
	print("============================================================")
	print("  Demo completed!")
	print("============================================================")
	print("")

func _setup_database() -> void:
	print("")
	print("--- Step 1: Set up database ---")
	DirAccess.make_dir_recursive_absolute(_db_path)
	var root_conf_path = _db_path.path_join("config.cfg")
	if not FileAccess.file_exists(root_conf_path):
		var cfg = ConfigFile.new()
		cfg.set_value("demo_data", "data_path", _db_path)
		cfg.set_value("demo_data", "encrypted", "")
		cfg.save(root_conf_path)
	print("Database: " + _db_path)

func _create_hero_table() -> void:
	print("")
	print("--- Step 2: Create table ---")
	var table_conf_path = _db_path.path_join("hero.cfg")
	var table_cfg = ConfigFile.new()
	table_cfg.set_value("hero", "columns", [
		{"Column Name": "id", "Data Type": 2, "PK": true, "AI": true, "NN": true},
		{"Column Name": "name", "Data Type": 4, "PK": false},
		{"Column Name": "hp", "Data Type": 2, "PK": false},
		{"Column Name": "mp", "Data Type": 2, "PK": false},
		{"Column Name": "class_type", "Data Type": 4, "PK": false}
	])
	table_cfg.save(table_conf_path)
	print("Table 'hero': id, name, hp, mp, class_type")

func _insert_heroes() -> void:
	print("")
	print("--- Step 3: Insert records ---")
	for hero in [
		{"id": 1, "name": "Arthur", "hp": 320, "mp": 100, "class_type": "Knight"},
		{"id": 2, "name": "Merlin", "hp": 180, "mp": 300, "class_type": "Mage"},
		{"id": 3, "name": "Robin", "hp": 220, "mp": 150, "class_type": "Archer"},
		{"id": 4, "name": "Brunhild", "hp": 280, "mp": 80, "class_type": "Warrior"}
	]:
		var dao = GDSQL.BaseDao.new()
		var ret = dao.use_db(_db_path).insert_into("hero.gsql").primary_key("id", true).values(hero).query()
		if ret and ret.ok():
			print("  Inserted: " + hero["name"])

func _select_heroes() -> void:
	print("")
	print("--- Step 4: Query all heroes ---")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).select("*", true).from("hero.gsql").query()
	if ret and ret.ok():
		print("  Found %d hero(es):" % ret.get_data().size())
		for row in ret.get_data():
			print("    [%d] %-12s HP=%-4d MP=%-4d %s" % [
				row.get("id", 0), row.get("name", ""),
				row.get("hp", 0), row.get("mp", 0), row.get("class_type", "")
			])

func _select_heroes_with_condition() -> void:
	print("")
	print("--- Step 5: Query with conditions ---")
	print("  Heroes with HP > 200:")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).select("id, name, hp, class_type", false).from("hero.gsql").where("hp > 200").order_by("hp", GDSQL.ORDER_BY.DESC).query()
	if ret and ret.ok():
		for row in ret.get_data():
			print("    %-12s HP=%d" % [row.get("name", ""), row.get("hp", 0)])

func _update_hero() -> void:
	print("")
	print("--- Step 6: Update Arthur's HP to 500 ---")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).update("hero.gsql").sets({"hp": 500}).where("name == 'Arthur'").query()
	if ret and ret.ok():
		print("  Updated")

func _verify_update() -> void:
	print("")
	print("--- Step 7: Verify update ---")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).select("name, hp", false).from("hero.gsql").where("name == 'Arthur'").query()
	if ret and ret.ok() and ret.get_data().size() > 0:
		var hp = ret.get_data()[0].get("hp", 0)
		print("  Arthur HP = " + str(hp))
		if hp == 500: print("  [PASS]")

func _delete_hero() -> void:
	print("")
	print("--- Step 8: Delete Brunhild ---")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).delete_from("hero.gsql").where("name == 'Brunhild'").query()
	if ret and ret.ok():
		print("  Deleted")

func _verify_deletion() -> void:
	print("")
	print("--- Step 9: Verify deletion ---")
	var dao = GDSQL.BaseDao.new()
	var ret = dao.use_db(_db_path).select("count(*) as c", true).from("hero.gsql").where("name == 'Brunhild'").query()
	if ret and ret.ok() and ret.get_data().size() > 0 and ret.get_data()[0].get("c", -1) == 0:
		print("  Verified: Brunhild is gone [PASS]")
