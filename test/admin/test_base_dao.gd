extends GdUnitTestSuite

## Integration tests for GDSQL.BaseDao — fluent CRUD query API.

const TEST_DIR = "user://test_gdsql_base_dao/"
const TEST_ROOT_CFG = TEST_DIR + "config.cfg"
const TEST_DB = "_test_base_dao"
const TEST_TABLE = "users"
const TEST_DB_PATH = TEST_DIR + TEST_DB + "/"

var _dao: GDSQL.AdminDao
var _original_root_cfg_path: String

var _columns = [
	{"Column Name": "id",   "Data Type": TYPE_INT,    "PK": true,  "NN": true,  "AI": true,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
	{"Column Name": "name", "Data Type": TYPE_STRING, "PK": false, "NN": true,  "AI": false,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
	{"Column Name": "score","Data Type": TYPE_FLOAT,  "PK": false, "NN": false, "AI": false,
	 "UQ": false, "Index": false, "Default(Expression)": "", "Comment": ""},
]


func before_test() -> void:
	var rc = GDSQL.RootConfig
	_original_root_cfg_path = rc.path

	# Create test config dir if needed
	var dir_abs = ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)

	# Ensure test config file exists
	var cfg_abs = ProjectSettings.globalize_path(TEST_ROOT_CFG)
	if not FileAccess.file_exists(cfg_abs):
		ConfigFile.new().save(TEST_ROOT_CFG)

	# Redirect RootConfig to test config
	rc.set_path(TEST_ROOT_CFG)

	_dao = GDSQL.AdminDao.new()

	# If previous run left a database, drop it first
	if GDSQL.RootConfig.has_section(TEST_DB):
		await _dao.drop_database(TEST_DB)

	# Create fresh
	assert_int(_dao.create_database(TEST_DB, TEST_DB_PATH)).is_equal(OK)
	assert_int(await _dao.create_table(TEST_DB, TEST_TABLE, _columns)).is_equal(OK)


func after_test() -> void:
	if GDSQL.RootConfig.has_section(TEST_DB):
		await _dao.drop_database(TEST_DB)
	_dao = null
	GDSQL.RootConfig.set_path(_original_root_cfg_path)


func _bd() -> GDSQL.BaseDao:
	var bd = GDSQL.BaseDao.new()
	bd.use_db(TEST_DB)
	return bd


# --------------------------------------------------------------------------
# INSERT
# --------------------------------------------------------------------------

## 测试: INSERT 单行，验证自增 ID
func test_insert_single_row() -> void:
	var res = _bd().insert_into(TEST_TABLE).values({"name": "Alice", "score": 95.5}).query()
	assert_bool(res.ok()).is_true()
	assert_int(res.get_last_insert_id()).is_equal(1)

	var rows = _bd().select("*", false).from(TEST_TABLE).query().get_data()
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Alice")
	assert_float(rows[0][2]).is_equal(95.5)


## 测试: 自增主键连续递增
func test_auto_increment_sequence() -> void:
	for i in 3:
		_bd().insert_into(TEST_TABLE).values({"name": "U%d" % i, "score": i * 10}).query()
	var rows = _bd().select("id", false).from(TEST_TABLE).query().get_data()
	assert_int(rows.size()).is_equal(3)
	assert_int(rows[0][0]).is_equal(1)
	assert_int(rows[1][0]).is_equal(2)
	assert_int(rows[2][0]).is_equal(3)


# --------------------------------------------------------------------------
# SELECT
# --------------------------------------------------------------------------

## 测试: SELECT * 返回所有数据
func test_select_all() -> void:
	_bd().insert_into(TEST_TABLE).values({"name": "A", "score": 1}).query()
	_bd().insert_into(TEST_TABLE).values({"name": "B", "score": 2}).query()

	var rows = _bd().select("*", false).from(TEST_TABLE).query().get_data()
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0][1]).is_equal("A")
	assert_str(rows[1][1]).is_equal("B")


## 测试: SELECT WHERE 筛选
func test_select_where() -> void:
	_bd().insert_into(TEST_TABLE).values({"name": "High", "score": 100}).query()
	_bd().insert_into(TEST_TABLE).values({"name": "Low",  "score": 50}).query()

	var rows = _bd().select("*", false).from(TEST_TABLE).where("score > 60").query().get_data()
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("High")


## 测试: SELECT ORDER BY 排序
func test_select_order_by() -> void:
	_bd().insert_into(TEST_TABLE).values({"name": "C", "score": 70}).query()
	_bd().insert_into(TEST_TABLE).values({"name": "A", "score": 90}).query()
	_bd().insert_into(TEST_TABLE).values({"name": "B", "score": 80}).query()

	var rows = _bd().select("*", false).from(TEST_TABLE).order_by("score", GDSQL.ORDER_BY.ASC).query().get_data()
	assert_int(rows.size()).is_equal(3)
	assert_float(rows[0][2]).is_equal(70.0)
	assert_float(rows[1][2]).is_equal(80.0)
	assert_float(rows[2][2]).is_equal(90.0)


## 测试: SELECT LIMIT 限制
func test_select_limit() -> void:
	for i in 5:
		_bd().insert_into(TEST_TABLE).values({"name": "X%d" % i, "score": i}).query()

	var rows = _bd().select("*", false).from(TEST_TABLE).limit(0, 2).query().get_data()
	assert_int(rows.size()).is_equal(2)


# --------------------------------------------------------------------------
# UPDATE
# --------------------------------------------------------------------------

## 测试: UPDATE 更新字段
func test_update() -> void:
	_bd().insert_into(TEST_TABLE).values({"name": "Target", "score": 60}).query()
	_bd().update(TEST_TABLE).sets({"score": 99}).where("name == 'Target'").query()

	var rows = _bd().select("score", false).from(TEST_TABLE).where("name == 'Target'").query().get_data()
	assert_int(rows.size()).is_equal(1)
	assert_float(rows[0][0]).is_equal(99.0)


# --------------------------------------------------------------------------
# DELETE
# --------------------------------------------------------------------------

## 测试: DELETE 删除行
func test_delete() -> void:
	_bd().insert_into(TEST_TABLE).values({"name": "Keep", "score": 1}).query()
	_bd().insert_into(TEST_TABLE).values({"name": "Remove", "score": 2}).query()

	_bd().delete_from(TEST_TABLE).where("name == 'Remove'").query()

	var rows = _bd().select("*", false).from(TEST_TABLE).query().get_data()
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0][1]).is_equal("Keep")
