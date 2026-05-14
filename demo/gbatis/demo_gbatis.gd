@tool
extends Node2D

@export var hero_mapper: DemoHeroMapper = null
var _db_path = "user://demo_gbatis_db/"

func _ready() -> void:
	print("")
	print("============================================================")
	print("  Demo: GBatis - Ready!")
	print("============================================================")
	print("")
	print("Press SPACE to run.")
	print("")

func _input(event) -> void:
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		_run_demo()

func _run_demo() -> void:
	if hero_mapper == null:
		printerr("ERROR: hero_mapper not set!")
		return
	print("")
	print("============================================================")
	print("  Demo: GBatis")
	print("============================================================")
	DirAccess.make_dir_recursive_absolute(_db_path)
	# create table config
	var hc = ConfigFile.new()
	hc.set_value("hero", "columns", [
		{"Column Name": "id", "Data Type": 2, "PK": true, "AI": true},
		{"Column Name": "name", "Data Type": 4},
		{"Column Name": "hp", "Data Type": 2},
		{"Column Name": "mp", "Data Type": 2},
		{"Column Name": "class_type", "Data Type": 4}
	])
	hc.save(_db_path.path_join("hero.cfg"))
	# 1. Insert
	print("")
	print("--- 1. Insert via GBatis ---")
	var names = ["Arthur", "Merlin"]
	var hps = [320, 180]
	var mps = [100, 300]
	var classes = ["Knight", "Mage"]
	for i in range(2):
		var e = DemoHeroEntity.new()
		e.id = 0
		e.name = names[i]
		e.hp = hps[i]
		e.mp = mps[i]
		e.class_type = classes[i]
		var id = hero_mapper.insert_hero(e)
		print("  Inserted: %s (id=%d)" % [names[i], id])
	# 2. Select by id
	print("")
	print("--- 2. Select by id ---")
	var h = hero_mapper.select_hero_by_id(1) as DemoHeroEntity
	if h:
		print("  Found: %s (HP=%d)" % [h.name, h.hp])
	# 3. Filter
	print("")
	print("--- 3. Filter (HP>=200) ---")
	var arr = hero_mapper.select_heroes_by_min_hp(200) as Array
	for e in arr:
		var entity = e as DemoHeroEntity
		print("  %-10s HP=%d" % [entity.name, entity.hp])
	# 4. Update
	print("")
	print("--- 4. Update ---")
	var aff = hero_mapper.update_hero_hp(1, 500)
	print("  Rows affected: %d" % aff)
	# 5. Delete
	print("")
	print("--- 5. Delete ---")
	aff = hero_mapper.delete_hero_by_id(2)
	print("  Rows deleted: %d" % aff)
	print("")
	print("GBatis demo completed.")
	print("")


