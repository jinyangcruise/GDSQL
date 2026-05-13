@tool
extends Node2D
var _pass := 0; var _fail := 0
var _db := "user://test_base_dao/"; var _t := "items.gsql"
func _ready():
    print("\n"+"="*60+"\n  Test: BaseDao CRUD\n"+"="*60+"\n")
    _setup(); t_insert(); t_select_all(); t_select_where(); t_select_order()
    t_update(); t_delete(); t_transaction(); _summary()
func ok(d): _pass+=1; print("  [PASS] "+d)
func nt(d,s=""): _fail+=1; printerr("  [FAIL] "+d+" - "+s)
func _summary(): print("\n  %d passed, %d failed\n%s\n" % [_pass,_fail,"="*60])
func _setup():
    DirAccess.make_dir_recursive_absolute(_db)
    var c := ConfigFile.new()
    c.set_value("items","columns",[{"Column Name":"id","Data Type":2,"PK":true,"AI":true},{"Column Name":"name","Data Type":4},{"Column Name":"val","Data Type":2},{"Column Name":"act","Data Type":1}])
    c.save(_db.path_join("items.cfg"))
func _cln(): GDSQL.BaseDao.new().use_db(_db).delete_from(_t).query()
func t_insert():
    _cln()
    var r = GDSQL.BaseDao.new().use_db(_db).insert_into(_t).primary_key("id",true).values({"name":"a","val":100,"act":true}).query()
    if r and r.ok(): ok("Insert one")
    var n:=0
    for i in range(3):
        r = GDSQL.BaseDao.new().use_db(_db).insert_into(_t).primary_key("id",true).values({"name":"x%d"%i,"val":i}).query()
        if r and r.ok(): n+=1
    if n==3: ok("Insert batch 3")
func t_select_all():
    _cln()
    for i in range(3): GDSQL.BaseDao.new().use_db(_db).insert_into(_t).primary_key("id",true).values({"name":"s%d"%i,"val":i}).query()
    var r = GDSQL.BaseDao.new().use_db(_db).select("*",true).from(_t).query()
    if r and r.ok() and r.get_data().size()==3: ok("SELECT * returns 3")
func t_select_where():
    var r = GDSQL.BaseDao.new().use_db(_db).select("*",true).from(_t).where("val >= 1").query()
    if r and r.ok() and r.get_data().size()>=2: ok("WHERE val>=1")
func t_select_order():
    var r = GDSQL.BaseDao.new().use_db(_db).select("val").from(_t).order_by("val",GDSQL.ORDER_BY.DESC).query()
    if r and r.ok() and r.get_data().size()>=2 and r.get_data()[0].get("val",-1)>=r.get_data()[1].get("val",-1): ok("ORDER BY DESC")
func t_update():
    var r = GDSQL.BaseDao.new().use_db(_db).update(_t).set({"val":999}).where("name == 's0'").query()
    if r and r.ok(): ok("Update")
    r = GDSQL.BaseDao.new().use_db(_db).select("val").from(_t).where("name == 's0'").query()
    if r and r.ok() and r.get_data().size()>0 and r.get_data()[0].get("val",0)==999: ok("Verify update")
func t_delete():
    var r = GDSQL.BaseDao.new().use_db(_db).delete_from(_t).where("name == 's0'").query()
    if r and r.ok(): ok("Delete")
    r = GDSQL.BaseDao.new().use_db(_db).select("count(*) as c").from(_t).where("name == 's0'").query()
    if r and r.ok() and r.get_data().size()>0 and r.get_data()[0].get("c",-1)==0: ok("Verify deletion")
func t_transaction():
    _cln()
    var d := GDSQL.BaseDao.new(); d.use_db(_db).auto_commit(false)
    d.insert_into(_t).primary_key("id",true).values({"name":"tx1","val":1}).query()
    if d.commit() == OK: ok("Transaction commit")
    d = GDSQL.BaseDao.new(); d.use_db(_db).auto_commit(false)
    d.insert_into(_t).primary_key("id",true).values({"name":"tx2","val":2}).query()
    if d.rollback() == OK: ok("Transaction rollback")
    var r = GDSQL.BaseDao.new().use_db(_db).select("*",true).from(_t).query()
    if r and r.ok() and r.get_data().size()==1: ok("Rollback: no persisted")
