@tool
extends Node2D

var _pass = 0; var _fail = 0
var _db = "user://test_base_dao/"
var _t = "items.gsql"

func _ready() -> void:
	print("")
	print("============================================================")
	print("  Test: BaseDao CRUD")
	print("============================================================")
	print("")
	_setup()
	t_insert()
	t_select_all()
	t_select_where()
	t_select_order()
	t_update()
	t_delete()
	t_transaction()
	_summary()

func ok(d) -> void:
	_pass += 1
	print("  [PASS] " + d)

func nt(d, s = "") -> void:
	_fail += 1
	printerr("  [FAIL] " + d + " - " + s)

func _summary() -> void:
	print("")
	print("  %d passed, %d failed" % [_pass, _fail])
	print("============================================================")
	print("")

func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(_db)
	var c = ConfigFile.new()
	c.set_value("items", "columns", [
		{"Column Name": "id", "Data Type": 2, "PK": true, "AI": true},
		{"Column Name": "name", "Data Type": 4},
		{"Column Name": "val", "Data Type": 2},
		{"Column Name": "act", "Data Type": 1}
	])
	c.save(_db.path_join("items.cfg"))

func _cln() -> void:
	GDSQL.BaseDao.new().use_db(_db).delete_from(_t).query()

func t_insert() -> void:
	_cln()
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).insert_into(_t).primary_key("id", true).values({"name": "a", "val": 100, "act": true}).query()
	if r and r.ok(): ok("Insert one")
	var n = 0
	for i in range(3):
		var d2 = GDSQL.BaseDao.new()
		var r2 = d2.use_db(_db).insert_into(_t).primary_key("id", true).values({"name": "x%d" % i, "val": i}).query()
		if r2 and r2.ok(): n += 1
	if n == 3: ok("Insert batch 3")

func t_select_all() -> void:
	_cln()
	for i in range(3):
		var d = GDSQL.BaseDao.new()
		d.use_db(_db).insert_into(_t).primary_key("id", true).values({"name": "s%d" % i, "val": i}).query()
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).select("*", true).from(_t).query()
	if r and r.ok() and r.get_data().size() == 3: ok("SELECT * returns 3")

func t_select_where() -> void:
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).select("*", true).from(_t).where("val >= 1").query()
	if r and r.ok() and r.get_data().size() >= 2: ok("WHERE val>=1")

func t_select_order() -> void:
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).select("val", false).from(_t).order_by("val", GDSQL.ORDER_BY.DESC).query()
	if r and r.ok() and r.get_data().size() >= 2:
		if r.get_data()[0].get("val", -1) >= r.get_data()[1].get("val", -1): ok("ORDER BY DESC")

func t_update() -> void:
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).update(_t).sets({"val": 999}).where("name == 's0'").query()
	if r and r.ok(): ok("Update")
	var d2 = GDSQL.BaseDao.new()
	var r2 = d2.use_db(_db).select("val", false).from(_t).where("name == 's0'").query()
	if r2 and r2.ok() and r2.get_data().size() > 0 and r2.get_data()[0].get("val", 0) == 999: ok("Verify update")

func t_delete() -> void:
	var dao = GDSQL.BaseDao.new()
	var r = dao.use_db(_db).delete_from(_t).where("name == 's0'").query()
	if r and r.ok(): ok("Delete")
	var d2 = GDSQL.BaseDao.new()
	var r2 = d2.use_db(_db).select("count(*) as c", true).from(_t).where("name == 's0'").query()
	if r2 and r2.ok() and r2.get_data().size() > 0 and r2.get_data()[0].get("c", -1) == 0: ok("Verify deletion")

func t_transaction() -> void:
	_cln()
	var dao = GDSQL.BaseDao.new()
	dao.use_db(_db).auto_commit(false)
	dao.insert_into(_t).primary_key("id", true).values({"name": "tx1", "val": 1}).query()
	dao.commit()
	ok("Transaction commit")
	var d2 = GDSQL.BaseDao.new()
	d2.use_db(_db).auto_commit(false)
	d2.insert_into(_t).primary_key("id", true).values({"name": "tx2", "val": 2}).query()
	d2.rollback()
	ok("Transaction rollback")
	var d3 = GDSQL.BaseDao.new()
	var r3 = d3.use_db(_db).select("*", true).from(_t).query()
	if r3 and r3.ok() and r3.get_data().size() == 1: ok("Rollback: no persisted")
