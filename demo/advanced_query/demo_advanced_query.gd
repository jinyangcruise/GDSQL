@tool
extends Node2D

var _db_path := "user://demo_advanced_db/"

func _ready():
    print("")
    print("============================================================")
    print("  Demo: Advanced Queries - Ready!")
    print("============================================================")
    print("")
    print("Press SPACE to run.")
    print("")

func _input(event):
    if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
        _run_all()

func _run_all():
    print("")
    print("============================================================")
    print("  Demo: Advanced Queries")
    print("============================================================")
    _setup_data()
    _demo_left_join()
    _demo_aggregate_group_by()
    _demo_subquery()
    _demo_union_all()
    _demo_pagination()
    print("")
    print("All advanced query demos completed.")
    print("")

func _setup_data():
    DirAccess.make_dir_recursive_absolute(_db_path)
    var gc := ConfigFile.new()
    gc.set_value("guild", "columns", [
        {"Column Name": "id", "Data Type": 2, "PK": true},
        {"Column Name": "name", "Data Type": 4},
        {"Column Name": "faction", "Data Type": 4}
    ])
    gc.save(_db_path.path_join("guild.cfg"))
    var hc := ConfigFile.new()
    hc.set_value("hero", "columns", [
        {"Column Name": "id", "Data Type": 2, "PK": true},
        {"Column Name": "name", "Data Type": 4},
        {"Column Name": "hp", "Data Type": 2},
        {"Column Name": "guild_id", "Data Type": 2}
    ])
    hc.save(_db_path.path_join("hero.cfg"))
    var guilds = [
        {"id": 1, "name": "Crimson Blades", "faction": "Alliance"},
        {"id": 2, "name": "Shadow Walkers", "faction": "Horde"},
        {"id": 3, "name": "Arcane Circle", "faction": "Alliance"}
    ]
    for g in guilds:
        GDSQL.BaseDao.new().use_db(_db_path).insert_into("guild.gsql").primary_key("id", true).values(g).query()
    var heroes = [
        {"id": 1, "name": "Arthur", "hp": 320, "guild_id": 1},
        {"id": 2, "name": "Merlin", "hp": 180, "guild_id": 3},
        {"id": 3, "name": "Robin", "hp": 220, "guild_id": 1},
        {"id": 4, "name": "Brunhild", "hp": 280, "guild_id": 2},
        {"id": 5, "name": "Luna", "hp": 200, "guild_id": 3},
        {"id": 6, "name": "Kael", "hp": 350, "guild_id": 2}
    ]
    for h in heroes:
        GDSQL.BaseDao.new().use_db(_db_path).insert_into("hero.gsql").primary_key("id", true).values(h).query()
    print("")
    print("--- Data: 3 guilds, 6 heroes ---")

func _demo_left_join():
    print("")
    print("--- LEFT JOIN ---")
    var dao := GDSQL.BaseDao.new()
    var ret := dao.use_db(_db_path).select("h.name, h.hp, g.name as guild, g.faction", true).from("hero.gsql", "h").left_join("", "guild.gsql", "g", "h.guild_id == g.id", "").order_by("h.hp", GDSQL.ORDER_BY.DESC).query()
    if ret and ret.ok():
        for r in ret.get_data():
            print("  %-10s HP=%-4d Guild: %s (%s)" % [r.get("name", ""), r.get("hp", 0), r.get("guild", ""), r.get("faction", "")])

func _demo_aggregate_group_by():
    print("")
    print("--- GROUP BY + COUNT/AVG ---")
    var dao := GDSQL.BaseDao.new()
    var ret := dao.use_db(_db_path).select("g.name, count(h.id) as cnt, avg(h.hp) as avg_hp", true).from("hero.gsql", "h").left_join("", "guild.gsql", "g", "h.guild_id == g.id", "").group_by("h.guild_id").order_by("cnt", GDSQL.ORDER_BY.DESC).query()
    if ret and ret.ok():
        for r in ret.get_data():
            print("  %-16s Heroes: %d  Avg HP: %.1f" % [r.get("name", ""), r.get("cnt", 0), r.get("avg_hp", 0.0)])

func _demo_subquery():
    print("")
    print("--- Subquery: Above average HP ---")
    var dao := GDSQL.BaseDao.new()
    var ret := dao.use_db(_db_path).select("name, hp").from("hero.gsql").where("hp > (select avg(hp) from hero.gsql)").order_by("hp", GDSQL.ORDER_BY.DESC).query()
    if ret and ret.ok():
        for r in ret.get_data():
            print("  %-10s HP=%d" % [r.get("name", ""), r.get("hp", 0)])

func _demo_union_all():
    print("")
    print("--- UNION ALL ---")
    var dao := GDSQL.BaseDao.new()
    var ret := dao.use_db(_db_path).select("name, hp, 'high' as tier", true).from("hero.gsql").where("hp >= 300").union_all().select_same().from("hero.gsql").where("hp < 200").order_by("hp", GDSQL.ORDER_BY.DESC).query()
    if ret and ret.ok():
        for r in ret.get_data():
            print("  %-10s HP=%-4d (%s)" % [r.get("name", ""), r.get("hp", 0), r.get("tier", "")])

func _demo_pagination():
    print("")
    print("--- LIMIT + OFFSET (page 2) ---")
    var dao := GDSQL.BaseDao.new()
    var ret := dao.use_db(_db_path).select("name, hp").from("hero.gsql").order_by("hp", GDSQL.ORDER_BY.DESC).limit(2, 1).query()
    if ret and ret.ok():
        for r in ret.get_data():
            print("  %-10s HP=%d" % [r.get("name", ""), r.get("hp", 0)])
