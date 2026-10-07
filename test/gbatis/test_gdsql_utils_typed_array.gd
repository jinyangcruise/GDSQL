extends GdUnitTestSuite

## Unit tests for the shared typed-array helpers added to GDSQL.GDSQLUtils:
##   make_typed_array(type_name)      — build an empty typed array by element type name
##   assign_to_typed(proto, data)     — fill a typed array WITHOUT silently losing data
##
## These are the consolidated implementations behind result_map.gd:_gen_array(),
## select.gd:_gen_array(), gbatis_entity.gd:_empty_typed_default()/_run_lazy_spec().

const ARRAY_TYPE := TYPE_ARRAY


# --------------------------------------------------------------------------
# make_typed_array — element type resolution
# --------------------------------------------------------------------------

## 测试: 内建元素类型
func test_make_typed_array_builtin() -> void:
	for t in ["int", "String", "float", "bool"]:
		var a = GDSQL.GDSQLUtils.make_typed_array(t)
		assert_array(a).is_not_null()
		assert_bool(a.is_typed()).override_failure_message("type=%s" % t).is_true()
		assert_array(a).is_empty()


## 测试: 内建元素类型的 builtin 与声明一致
func test_make_typed_array_builtin_ids() -> void:
	assert_int((GDSQL.GDSQLUtils.make_typed_array("int") as Array).get_typed_builtin()) \
		.is_equal(TYPE_INT)
	assert_int((GDSQL.GDSQLUtils.make_typed_array("String") as Array).get_typed_builtin()) \
		.is_equal(TYPE_STRING)


## 测试: 引擎类作为元素类型
func test_make_typed_array_engine_class() -> void:
	var a = GDSQL.GDSQLUtils.make_typed_array("RefCounted")
	assert_bool(a.is_typed()).is_true()
	assert_int(a.get_typed_builtin()).is_equal(TYPE_OBJECT)
	assert_array(a).is_empty()


## 测试: 用户实体类（class_name 注册的全局类）作为元素类型
func test_make_typed_array_user_entity_class() -> void:
	var a = GDSQL.GDSQLUtils.make_typed_array("GDSQLTestChildEntity")
	assert_bool(a.is_typed()).is_true()
	assert_int(a.get_typed_builtin()).is_equal(TYPE_OBJECT)
	assert_object(a.get_typed_script()).is_not_null()


## 测试: 带命名空间的类名（GDSQL.XXX）也可以
func test_make_typed_array_qualified_class() -> void:
	var a = GDSQL.GDSQLUtils.make_typed_array("GDSQL.GBatisEntity")
	assert_bool(a.is_typed()).is_true()
	assert_int(a.get_typed_builtin()).is_equal(TYPE_OBJECT)


## 测试: 空类型名返回 null（调用方自行决定回退）
func test_make_typed_array_empty_type_returns_null() -> void:
	assert_that(GDSQL.GDSQLUtils.make_typed_array("")).is_null()
	assert_that(GDSQL.GDSQLUtils.make_typed_array("   ")).is_null()


## 测试: 无法解析的类型名返回 null（引擎会报 Parse Error，但不会崩溃/卡住）
func test_make_typed_array_unknown_type_returns_null() -> void:
	await assert_error(
		func(): GDSQL.GDSQLUtils.make_typed_array("NoSuchClassAtAll"),
	).is_runtime_error('Parse Error: Could not find type "NoSuchClassAtAll" in the current scope.')


## 测试: 每次返回的是独立实例（调用方可以放心 assign/append）
func test_make_typed_array_returns_independent_instances() -> void:
	var a = GDSQL.GDSQLUtils.make_typed_array("int")
	var b = GDSQL.GDSQLUtils.make_typed_array("int")
	a.push_back(1)
	assert_array(a).has_size(1)
	assert_array(b).is_empty()


# --------------------------------------------------------------------------
# assign_to_typed — never lose data
# --------------------------------------------------------------------------

## 测试: 元素类型一致时正常转换，并保持 typed
func test_assign_to_typed_same_element_type() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("int")
	var ret = GDSQL.GDSQLUtils.assign_to_typed(proto, [1, 2, 3])

	assert_array(ret).contains_exactly([1, 2, 3])
	assert_bool(ret.is_typed()).is_true()
	assert_int(ret.get_typed_builtin()).is_equal(TYPE_INT)


## 测试: 元素类型不兼容时**保留全部数据**（退回原始数组），而不是静默变成空集合。
## 这是本次修复的核心不变量：Array.assign() 转换失败只会留下空数组且不报错。
func test_assign_to_typed_incompatible_keeps_all_data() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("RefCounted")
	var data: Array = [1, 2, 3]

	var ret = GDSQL.GDSQLUtils.assign_to_typed(proto, data)

	assert_int(ret.size()).is_equal(3)
	assert_array(ret).contains_exactly([1, 2, 3])


## 测试: 对照 —— 直接 assign 确实会丢数据（记录的引擎行为，防止以后误改回去）
func test_raw_assign_loses_data_on_mismatch() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("RefCounted")
	var lost: Array = proto.duplicate()
	lost.assign([1, 2, 3])

	assert_array(lost).is_empty() # assign 失败后是空数组，不是 3 个元素


## 测试: 引擎支持的元素转换仍然生效（int -> float），并保持 typed
func test_assign_to_typed_numeric_conversion() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("float")
	var ret = GDSQL.GDSQLUtils.assign_to_typed(proto, [1, 2])

	assert_int(ret.size()).is_equal(2)
	assert_bool(ret.is_typed()).is_true()
	assert_float(ret[0]).is_equal(1.0)


## 测试: 引擎**不做**的转换（int -> String）不丢数据，
## 只是容器退化成无类型数组 —— 这正是"宁可类型退化，也不能丢数据"。
func test_assign_to_typed_incompatible_int_to_string_keeps_elements() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("String")
	var ret = GDSQL.GDSQLUtils.assign_to_typed(proto, [1, 2])

	assert_int(ret.size()).is_equal(2)
	assert_int(ret[0]).is_equal(1)


## 测试: 空数据返回空 typed 数组
func test_assign_to_typed_empty_data() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("int")
	var ret = GDSQL.GDSQLUtils.assign_to_typed(proto, [])

	assert_array(ret).is_empty()
	assert_bool(ret.is_typed()).is_true()


## 测试: 元素类型一致时不会改动传入的 proto 本身
func test_assign_to_typed_does_not_mutate_proto() -> void:
	var proto: Array = GDSQL.GDSQLUtils.make_typed_array("int")
	GDSQL.GDSQLUtils.assign_to_typed(proto, [1, 2])

	assert_array(proto).is_empty()


# --------------------------------------------------------------------------
# The consolidation itself: all 4 former implementations agree
# --------------------------------------------------------------------------

## 测试: result_map._gen_array() 与共享实现产出等价的 typed 数组
func test_result_map_gen_array_delegates_to_shared_helper() -> void:
	var rm = GDSQL.GBatisResultMap.new({ })
	for t in ["int", "String", "RefCounted"]:
		var from_rm = rm._gen_array(t)
		var direct = GDSQL.GDSQLUtils.make_typed_array(t)
		assert_bool(from_rm.is_typed()).override_failure_message("type=%s" % t).is_true()
		assert_int(from_rm.get_typed_builtin()).is_equal(direct.get_typed_builtin())


## 测试: result_map._gen_array("") 仍然返回普通空数组（保持原有约定）
func test_result_map_gen_array_empty_type() -> void:
	var rm = GDSQL.GBatisResultMap.new({ })
	var ret = rm._gen_array("")

	assert_array(ret).is_empty()
	assert_bool(ret.is_typed()).is_false()


## 测试: gbatis_entity._empty_typed_default() 对 Array[实体] 属性产出 typed 空数组
func test_empty_typed_default_uses_shared_helper() -> void:
	var e = GDSQLTestParentEntity.new()
	var expected = GDSQL.GDSQLUtils.make_typed_array("GDSQLTestChildEntity")
	assert_that(expected).is_not_null()

	var ret = e._empty_typed_default("items")

	assert_array(ret).is_not_null()
	assert_bool(ret.is_typed()).is_true()
	assert_int(ret.get_typed_builtin()).is_equal(expected.get_typed_builtin())
	assert_array(ret).is_empty()


## 测试: 非数组属性返回 null
func test_empty_typed_default_non_array_property() -> void:
	var e = GDSQLTestParentEntity.new()

	assert_that(e._empty_typed_default("id")).is_null()
	assert_that(e._empty_typed_default("no_such_property")).is_null()
