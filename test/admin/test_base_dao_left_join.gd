extends GdUnitTestSuite

## Unit tests for commit 4b03ab4 — "Efficiency of table join queries under certain conditions".
##
## That commit adds two early-exit optimizations to BaseDao.___select():
##   A) `empty_equality_constraint`: an equality constraint on a main-table primary key /
##      indexed column that matches *no* section means the candidate set is empty.
##   B) `main_table_empty`: when the main table's candidate set is empty, the joined
##      tables are not loaded at all.
##
## Both are pure optimizations, so every test here also pins the observable result the
## non-optimized path produced — especially the LEFT JOIN contract that an unmatched
## left row must still be returned with NULLs for the joined columns.

const TEST_DIR = "user://test_gdsql_join/"
const TEST_ROOT_CFG = TEST_DIR + "config.cfg"
const TEST_DB = "_test_join_opt"
const TEST_DB_PATH = TEST_DIR + TEST_DB + "/"
const MAIN_TABLE = "users"
const JOIN_TABLE = "details"

var _dao: GDSQL.AdminDao
var _original_root_cfg_path: String

var _main_columns = [
	{"Column Name": "id",   "Data Type": TYPE_INT,    "PK": true,  "NN": true,  "AI": true,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
	{"Column Name": "name", "Data Type": TYPE_STRING, "PK": false, "NN": true,  "AI": false,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
	{"Column Name": "age",  "Data Type": TYPE_INT,    "PK": false, "NN": false, "AI": false,
	 "UQ": false, "Index": true,  "Default(Expression)": "", "Comment": ""},
]
var _join_columns = [
	{"Column Name": "id",     "Data Type": TYPE_INT,    "PK": true,  "NN": true,  "AI": true,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
	{"Column Name": "uid",    "Data Type": TYPE_INT,    "PK": false, "NN": true,  "AI": false,
	 "UQ": false, "Index": true,  "Default(Expression)": "", "Comment": ""},
	{"Column Name": "note",   "Data Type": TYPE_STRING, "PK": false, "NN": false, "AI": false,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
]


func before_test() -> void:
	var rc = GDSQL.RootConfig
	_original_root_cfg_path = rc.path

	var dir_abs = ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
	if not FileAccess.file_exists(ProjectSettings.globalize_path(TEST_ROOT_CFG)):
		ConfigFile.new().save(TEST_ROOT_CFG)

	rc.set_path(TEST_ROOT_CFG)
	_dao = GDSQL.AdminDao.new()

	if GDSQL.RootConfig.has_section(TEST_DB):
		await _dao.drop_database(TEST_DB)

	assert_int(_dao.create_database(TEST_DB, TEST_DB_PATH)).is_equal(OK)
	assert_int(await _dao.create_table(TEST_DB, MAIN_TABLE, _main_columns)).is_equal(OK)
	assert_int(await _dao.create_table(TEST_DB, JOIN_TABLE, _join_columns)).is_equal(OK)

	_seed()


func after_test() -> void:
	if GDSQL.RootConfig.has_section(TEST_DB):
		await _dao.drop_database(TEST_DB)
	_dao = null
	GDSQL.RootConfig.set_path(_original_root_cfg_path)


## 主表 users: (1,"Alice",30) (2,"Bob",40) (3,"Carol",50)
## 联表 details: 只有 uid=1 和 uid=3 有明细，uid=2 没有（用于验证 LEFT JOIN 补 NULL）
## NOTICE 每次 insert 都要用新的 BaseDao：同一个实例的 __cmd 已被占用，复用会静默失败。
func _seed() -> void:
	_bd().insert_into(MAIN_TABLE).values({"name": "Alice", "age": 30}).query()
	_bd().insert_into(MAIN_TABLE).values({"name": "Bob", "age": 40}).query()
	_bd().insert_into(MAIN_TABLE).values({"name": "Carol", "age": 50}).query()
	_bd().insert_into(JOIN_TABLE).values({"uid": 1, "note": "n1"}).query()
	_bd().insert_into(JOIN_TABLE).values({"uid": 3, "note": "n3"}).query()


func _bd() -> GDSQL.BaseDao:
	var bd = GDSQL.BaseDao.new()
	bd.use_db(TEST_DB)
	return bd


## 左联查询：主表别名 u，联表别名 d，按 u.id == d.uid 关联
func _join_query(where_clause: String) -> GDSQL.QueryResult:
	var bd := _bd()
	bd.select("u.id, u.name, d.note", false) \
		.from(MAIN_TABLE, "u") \
		.left_join(TEST_DB, JOIN_TABLE, "d", "u.id == d.uid", "") \
		.where(where_clause)
	return bd.query()


# --------------------------------------------------------------------------
# Baseline LEFT JOIN semantics (must not be altered by the optimization)
# --------------------------------------------------------------------------

## 测试: 无 WHERE 时所有主表行都返回；联表无匹配的行补 NULL
func test_left_join_keeps_unmatched_left_rows() -> void:
	var rows = _join_query("1 == 1").get_data()

	assert_int(rows.size()).is_equal(3)
	var by_name := { }
	for r in rows:
		by_name[r[1]] = r[2]
	assert_str(by_name["Alice"]).is_equal("n1")
	assert_that(by_name["Bob"]).is_null()      # uid=2 无明细 → 补 NULL
	assert_str(by_name["Carol"]).is_equal("n3")


## 测试: 命中主键等值约束时只返回该行，并带上联表数据
func test_left_join_where_matching_pk() -> void:
	var rows = _join_query("u.id == 1").get_data()

	assert_int(rows.size()).is_equal(1)
	assert_int(rows[0][0]).is_equal(1)
	assert_str(rows[0][1]).is_equal("Alice")
	assert_str(rows[0][2]).is_equal("n1")


## 测试: 命中索引列等值约束
func test_left_join_where_matching_indexed_column() -> void:
	var rows = _join_query("u.age == 40").get_data()

	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Bob")
	assert_that(rows[0][2]).is_null()


## 测试: 命中的主表行即使没有联表匹配，也必须返回（LEFT JOIN 语义）
func test_left_join_matching_left_row_without_join_match() -> void:
	var rows = _join_query("u.id == 2").get_data()

	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Bob")
	assert_that(rows[0][2]).is_null()


# --------------------------------------------------------------------------
# Optimization A: empty equality constraint on the main table
# --------------------------------------------------------------------------

## 测试: 主表主键等值约束在整表里查无匹配 → 结果为空（优化前会退化成全量数据 join）
func test_empty_pk_constraint_yields_empty_result() -> void:
	var rows = _join_query("u.id == 999").get_data()

	assert_array(rows).is_empty()


## 测试: 主表索引列等值约束查无匹配 → 结果为空
func test_empty_indexed_constraint_yields_empty_result() -> void:
	var rows = _join_query("u.age == 999").get_data()

	assert_array(rows).is_empty()


## 测试: 同一 WHERE 中后一列无法预筛（!= 导致 break）时，仍需返回空结果。
## 合取语义下"某一列等值无匹配"已经足以判定整个 WHERE 不可能命中，
## 因此 empty_equality_constraint 在 break 之后必须依然生效。
func test_empty_constraint_not_reset_by_later_unfilterable_column() -> void:
	var rows = _join_query("u.id == 999 and u.name != 'zzz'").get_data()

	assert_array(rows).is_empty()


## 测试: 有匹配的等值约束不能被误判为空
func test_matching_pk_constraint_is_not_empty() -> void:
	var rows = _join_query("u.id == 3").get_data()

	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Carol")


## 测试: IN 列表全部无匹配 → 结果为空
func test_in_constraint_without_match_yields_empty_result() -> void:
	var rows = _join_query("u.id in [998, 999]").get_data()

	assert_array(rows).is_empty()


## 测试: IN 列表部分匹配时不能误判为空
func test_in_constraint_partially_matching_keeps_rows() -> void:
	var rows = _join_query("u.id in [1, 999]").get_data()

	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Alice")


# --------------------------------------------------------------------------
# Optimization A must NOT be applied to joined tables
# --------------------------------------------------------------------------

## 测试: 联表的 ON 条件含"整表都匹配不到"的合取等值项时，LEFT JOIN 仍必须保留左行（补 NULL）。
## 这是 empty_equality_constraint 只对主表生效（table_alias == __table_alias）的关键防线：
## 若把这个优化也套到联表上，这里会把 3 行正确结果错误地变成 0 行。
func test_join_side_impossible_on_conjunct_keeps_left_rows() -> void:
	var bd := _bd()
	bd.select("u.id, u.name, d.note", false) \
		.from(MAIN_TABLE, "u") \
		.left_join(TEST_DB, JOIN_TABLE, "d", "u.id == d.uid and d.uid == 999", "")
	var rows = bd.query().get_data()

	assert_int(rows.size()).is_equal(3)
	for r in rows:
		assert_that(r[2]).is_null()


## 测试: 对照 —— 同样把 d.uid == 999 放进 WHERE（真正的过滤）时结果才应为空
func test_join_side_constraint_in_where_filters_all_rows() -> void:
	var rows = _join_query("d.uid == 999").get_data()

	assert_array(rows).is_empty()


# --------------------------------------------------------------------------
# Optimization B: skipped joined-table loading must not change the result shape
# --------------------------------------------------------------------------

## 测试: 主表候选集为空时跳过联表加载，返回的仍是空结果集（不是错误/表头）
func test_skipped_join_load_returns_empty() -> void:
	var res = _join_query("u.id == 999")

	assert_bool(res.ok()).is_true()
	assert_array(res.get_data()).is_empty()


## 测试: 未联表（left_join == null）时的空结果不受优化影响
func test_no_left_join_empty_result() -> void:
	var rows = _bd().select("*", false).from(MAIN_TABLE).where("id == 999").query().get_data()

	assert_array(rows).is_empty()
