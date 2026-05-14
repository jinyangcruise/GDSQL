@tool
extends Node2D

var _pass := 0; var _fail := 0

func _ready():
    print("")
    print("============================================================")
    print("  Test: SQL Parser")
    print("============================================================")
    print("")
    t_parse_simple()
    t_parse_where()
    t_parse_order_limit()
    t_parse_insert()
    t_parse_update()
    t_parse_delete()
    t_parse_left_join()
    t_parse_aggregate()
    _summary()

func ok(d):
    _pass += 1
    print("  [PASS] " + d)

func nt(d, s = ""):
    _fail += 1
    printerr("  [FAIL] " + d + " - " + s)

func _summary():
    print("")
    print("  %d passed, %d failed" % [_pass, _fail])
    print("============================================================")
    print("")

func _parse(s):
    var r = GDSQL.SQLParser.parse_to_dao(s)
    return r != null

func t_parse_simple():
    if _parse("select id, name from t"): ok("SELECT simple")
    if _parse("select * from t"): ok("SELECT *")

func t_parse_where():
    if _parse("select * from t where id == 1"): ok("WHERE ==")
    if _parse("select * from t where hp > 100 and mp < 50"): ok("WHERE AND")

func t_parse_order_limit():
    if _parse("select * from t order by id desc"): ok("ORDER BY DESC")
    if _parse("select * from t order by id asc limit 5"): ok("ORDER BY + LIMIT")

func t_parse_insert():
    if _parse("insert into t (id,name) values (1,'a')"): ok("INSERT INTO")

func t_parse_update():
    if _parse("update t set hp=500 where id==1"): ok("UPDATE SET")
    if _parse("update t set hp=500,mp=200 where id==1"): ok("UPDATE multi SET")

func t_parse_delete():
    if _parse("delete from t where id==1"): ok("DELETE WHERE")
    if _parse("delete from t"): ok("DELETE all")

func t_parse_left_join():
    if _parse("select a.* from t a left join t2 b on b.id == a.id"): ok("LEFT JOIN")

func t_parse_aggregate():
    if _parse("select type, count(*) as cnt from t group by type"): ok("GROUP BY")
    if _parse("select type, count(*) from t group by type having cnt > 1"): ok("HAVING")
