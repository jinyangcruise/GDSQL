@tool
extends Node2D

@export var hero_mapper: DemoHeroMapper = null
var _db_path := "user://demo_gbatis_db/"

func _ready() -> void:
    print("\n"+"="*60+"\n  Demo: GBatis - Ready!\n"+"="*60+"\nPress SPACE to run.\n")

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed: _run_demo()

func _run_demo() -> void:
    if hero_mapper == null: printerr("ERROR: hero_mapper not set!"); return
    print("\n"+"="*60+"\n  Demo: GBatis\n"+"="*60)
    DirAccess.make_dir_recursive_absolute(_db_path)
    var hc := ConfigFile.new()
    hc.set_value("hero","columns",[
        {"Column Name":"id","Data Type":2,"PK":true,"AI":true},
        {"Column Name":"name","Data Type":4},{"Column Name":"hp","Data Type":2},
        {"Column Name":"mp","Data Type":2},{"Column Name":"class_type","Data Type":4}])
    hc.save(_db_path.path_join("hero.cfg"))

    print("\n--- 1. Insert via GBatis ---")
    for d in [{"name":"Arthur","hp":320,"mp":100,"class_type":"Knight"},{"name":"Merlin","hp":180,"mp":300,"class_type":"Mage"}]:
        var e := DemoHeroEntity.new(); e.id=0; e.name=d.name; e.hp=d.hp; e.mp=d.mp; e.class_type=d.class_type
        var id := hero_mapper.insert_hero(e)
        print("  Inserted: %s (id=%d)" % [d.name, id])

    print("\n--- 2. Select by id ---")
    var h := hero_mapper.select_hero_by_id(1) as DemoHeroEntity
    if h: print("  Found: %s (HP=%d)" % [h.name, h.hp])

    print("\n--- 3. Filter (HP>=200) ---")
    for e in hero_mapper.select_heroes_by_min_hp(200) as Array:
        var entity := e as DemoHeroEntity
        print("  %-10s HP=%d" % [entity.name, entity.hp])

    print("\n--- 4. Update ---")
    var aff := hero_mapper.update_hero_hp(1, 500)
    print("  Rows affected: %d" % aff)

    print("\n--- 5. Delete ---")
    aff = hero_mapper.delete_hero_by_id(2)
    print("  Rows deleted: %d" % aff)
    print("\nGBatis demo completed.\n")
