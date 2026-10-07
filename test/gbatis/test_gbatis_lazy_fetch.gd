extends GdUnitTestSuite

## Unit tests for commit 439a310 — "Support lazy fetch for associations and collections".
##
## Covers the three moving parts of that change:
##   1. <association>/<collection> fetchType parsing + validation.
##   2. GDSQL.GBatisEntity lazy bookkeeping (set_lazy_spec / lazy_get / lazy_set /
##      is_lazy_loaded / invalidate_lazy) — registration must NOT query.
##   3. The typed-container contract: a lazily fetched collection must come back
##      with the same container type the eager path would have produced.

const SOURCE_BASIC := """extends GDSQL.GBatisEntity
var items: Array[int]
var child: RefCounted
var plain
"""
const SOURCE_CHILD := """extends GDSQL.GBatisEntity
var id = GDSQL.GBatisEntity.NULL
"""


# --------------------------------------------------------------------------
# fetchType attribute parsing (association.gd / collection.gd)
# --------------------------------------------------------------------------

## 测试: 未声明 fetchType 时默认 eager —— 保持改动前的行为，避免"未显式声明"的用户被改成懒加载
func test_association_default_fetch_type_is_eager() -> void:
	var ass = GDSQL.GBatisAssociation.new({"property": "child"})
	assert_str(ass.fetch_type).is_equal("eager")


## 测试: collection 未声明 fetchType 时默认 eager
func test_collection_default_fetch_type_is_eager() -> void:
	var col = GDSQL.GBatisCollection.new({"property": "children"})
	assert_str(col.fetch_type).is_equal("eager")


## 测试: fetchType="lazy" 且配置了 select 时生效
func test_association_fetch_type_lazy() -> void:
	var ass = GDSQL.GBatisAssociation.new({
		"property": "child",
		"column": "child_id",
		"select": "select_child",
		"fetchType": "lazy",
	})
	assert_str(ass.fetch_type).is_equal("lazy")


## 测试: collection 的 fetchType="lazy" 生效
func test_collection_fetch_type_lazy() -> void:
	var col = GDSQL.GBatisCollection.new({
		"property": "children",
		"column": "parent_id",
		"select": "select_children",
		"fetchType": "lazy",
	})
	assert_str(col.fetch_type).is_equal("lazy")


## 测试: fetchType 大小写与空白不敏感（" LAZY " 应被规范化）
func test_fetch_type_is_normalized() -> void:
	var ass = GDSQL.GBatisAssociation.new({
		"property": "child",
		"column": "child_id",
		"select": "select_child",
		"fetchType": "  LaZy ",
	})
	assert_str(ass.fetch_type).is_equal("lazy")


## 测试: fetchType="eager" 显式声明
func test_fetch_type_eager_explicit() -> void:
	var col = GDSQL.GBatisCollection.new({
		"property": "children",
		"column": "parent_id",
		"select": "select_children",
		"fetchType": "eager",
	})
	assert_str(col.fetch_type).is_equal("eager")


## 测试: lazy 但没有 select 时回退为 eager（惰加载无从发起查询，静默降级而非崩溃）
func test_lazy_without_select_falls_back_to_eager() -> void:
	var ass = GDSQL.GBatisAssociation.new({
		"property": "child",
		"column": "child_id",
		"fetchType": "lazy",
	})
	assert_str(ass.fetch_type).is_equal("eager")


## 测试: collection 的 lazy + 无 select 同样回退为 eager
func test_collection_lazy_without_select_falls_back_to_eager() -> void:
	var col = GDSQL.GBatisCollection.new({
		"property": "children",
		"column": "parent_id",
		"fetchType": "lazy",
	})
	assert_str(col.fetch_type).is_equal("eager")


## 测试: 非法 fetchType 触发断言失败（GDScript 的 assert 仅在调试构建生效）
## 注意: assert 在 GDScript 中无法被捕获，因此这里用 gdUnit 的错误断言来校验。
func test_invalid_fetch_type_asserts() -> void:
	if not OS.is_debug_build():
		return
	await assert_error(func(): GDSQL.GBatisAssociation.new({
		"property": "child",
		"column": "child_id",
		"select": "select_child",
		"fetchType": "lazyy",
	})).is_runtime_error("Assertion failed: Invalid fetchType 'lazyy' in <association> (expect lazy|eager).")


## 测试: collection 的非法 fetchType 触发断言失败
func test_collection_invalid_fetch_type_asserts() -> void:
	if not OS.is_debug_build():
		return
	await assert_error(func(): GDSQL.GBatisCollection.new({
		"property": "children",
		"column": "parent_id",
		"select": "select_children",
		"fetchType": "immediately",
	})).is_runtime_error("Assertion failed: Invalid fetchType 'immediately' in <collection> (expect lazy|eager).")


# --------------------------------------------------------------------------
# Registration: set_lazy_spec must only record, never fetch
# --------------------------------------------------------------------------

## 测试: set_lazy_spec 只登记，不触发任何查询（is_lazy_loaded 仍为 false）
func test_set_lazy_spec_does_not_fetch() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", [7]))

	assert_bool(e.is_lazy_loaded("items")).is_false()
	assert_int(parser.call_count).is_equal(0)


## 测试: set_lazy_spec 会清掉上一次登记的值，重新变为"未加载"
func test_set_lazy_spec_resets_previous_value() -> void:
	var e = _make_entity(SOURCE_BASIC)
	e.lazy_set("items", [1, 2, 3])
	assert_bool(e.is_lazy_loaded("items")).is_true()

	e.set_lazy_spec("items", _collection_spec(_RecordingParser.new(), "select_items", [7]))
	assert_bool(e.is_lazy_loaded("items")).is_false()


# --------------------------------------------------------------------------
# First access performs the fetch, subsequent accesses are cached
# --------------------------------------------------------------------------

## 测试: 首次 lazy_get 执行子查询并缓存，第二次访问不再查询
func test_lazy_get_fetches_once_and_caches() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	parser.result = [1, 2]
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", [7]))

	var first = e.lazy_get("items")
	var second = e.lazy_get("items")

	assert_array(first).contains_exactly([1, 2])
	assert_array(second).contains_exactly([1, 2])
	assert_int(parser.call_count).is_equal(1)
	assert_bool(e.is_lazy_loaded("items")).is_true()


## 测试: 子查询收到的参数就是登记时捕获的参数
func test_lazy_get_passes_registered_args() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_by_parent", [42]))

	e.lazy_get("items")

	assert_str(parser.last_select).is_equal("select_by_parent")
	assert_array(parser.last_args).contains_exactly([42])


## 测试: association 的懒加载返回值不做容器类型转换，原样返回
func test_lazy_get_association_returns_result_as_is() -> void:
	var parser := _RecordingParser.new()
	var child := RefCounted.new()
	parser.result = child
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("child", _association_spec(parser, "select_child"))

	assert_object(e.lazy_get("child")).is_same(child)


# --------------------------------------------------------------------------
# Typed container contract
# --------------------------------------------------------------------------

## 测试: 集合的懒加载结果被转成登记时生成的 typed 数组原型（与 eager 路径一致）
func test_lazy_get_collection_applies_typed_proto() -> void:
	var parser := _RecordingParser.new()
	var typed_proto: Array = Array([], TYPE_OBJECT, "RefCounted", null)
	parser.result = [RefCounted.new(), RefCounted.new()]
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", {
		"parser": weakref(parser),
		"select": "select_items",
		"args": [],
		"typed_proto": typed_proto,
	})

	var ret = e.lazy_get("items")

	assert_array(ret).has_size(2)
	assert_bool((ret as Array).is_typed()).is_true()


## 测试: 子查询返回空数组时不做转换，直接返回（保持空结果语义）
func test_lazy_get_empty_collection_result() -> void:
	var parser := _RecordingParser.new()
	parser.result = []
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", {
		"parser": weakref(parser),
		"select": "select_items",
		"args": [],
		"typed_proto": Array([], TYPE_OBJECT, "RefCounted", null),
	})

	assert_array(e.lazy_get("items")).is_empty()


## 测试: 元素类型不匹配时不得静默丢数据。
## Array.assign() 遇到无法转换的元素只会报错并留下**空数组**，若不校验就会把
## "查询到的 N 条数据"变成"空集合"（静默数据丢失）。eager 路径因此不会出现这种结果，
## 懒加载必须同样返回原始数据而不是空集合。
func test_lazy_get_collection_type_mismatch_keeps_data() -> void:
	var parser := _RecordingParser.new()
	parser.result = [1, 2, 3] # 标量结果
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", {
		"parser": weakref(parser),
		"select": "select_items",
		"args": [],
		"typed_proto": Array([], TYPE_OBJECT, "RefCounted", null), # 却按对象数组原型转换
	})

	var ret = e.lazy_get("items")

	assert_array(ret).has_size(3)
	assert_array(ret).contains_exactly([1, 2, 3])


## 测试: 未登记懒加载的集合属性返回空的 typed 容器，而不是 null
## （保证 for/in 不会因为拿到 null 而崩溃）
func test_unregistered_collection_returns_empty_typed_array() -> void:
	var e = _make_entity(SOURCE_BASIC)

	var ret = e.lazy_get("items")

	assert_array(ret).is_not_null()
	assert_array(ret).is_empty()
	assert_bool((ret as Array).is_typed()).is_true()


## 测试: 未登记懒加载的非数组属性返回 null
func test_unregistered_scalar_returns_null() -> void:
	var e = _make_entity(SOURCE_BASIC)

	assert_that(e.lazy_get("plain")).is_null()


# --------------------------------------------------------------------------
# Failure / invalidation paths
# --------------------------------------------------------------------------

## 测试: mapper 已被释放（WeakRef 失效）时返回 null 而不是崩溃
func test_lazy_get_with_dead_parser_returns_null() -> void:
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", {
		"parser": weakref(_RecordingParser.new()), # 立即失去强引用
		"select": "select_items",
		"args": [],
		"typed_proto": null,
	})

	assert_that(e.lazy_get("items")).is_null()
	assert_bool(e.is_lazy_loaded("items")).is_true() # 已尝试过，不再反复重试


## 测试: select 名为空时返回 null（防御性分支）
func test_lazy_get_with_empty_select_returns_null() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "", []))

	assert_that(e.lazy_get("items")).is_null()
	assert_int(parser.call_count).is_equal(0)


## 测试: invalidate_lazy(property) 使该属性下次访问重新查询
func test_invalidate_single_property_refetches() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))
	e.lazy_get("items")
	assert_int(parser.call_count).is_equal(1)

	e.invalidate_lazy("items")
	assert_bool(e.is_lazy_loaded("items")).is_false()

	e.lazy_get("items")
	assert_int(parser.call_count).is_equal(2)


## 测试: invalidate_lazy(property) 会丢掉旧值，下次访问拿到的是新查询结果
func test_invalidate_single_property_drops_stale_value() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	parser.result = [1]
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))
	assert_array(e.lazy_get("items")).contains_exactly([1])

	parser.result = [2, 3]
	e.invalidate_lazy("items")

	assert_array(e.lazy_get("items")).contains_exactly([2, 3])


## 测试: invalidate_lazy() 无参调用只丢弃全部缓存值，**保留登记**，
## 因此每个属性下次访问都会重新查询（这正是"写入后重新读取"所需的语义）。
func test_invalidate_all_keeps_specs_and_refetches() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))
	e.lazy_get("items") # 触发一次懒查询，使 items 处于"已加载"
	assert_bool(e.is_lazy_loaded("items")).is_true()
	assert_int(parser.call_count).is_equal(1)

	e.invalidate_lazy()

	assert_bool(e.is_lazy_loaded("items")).is_false()
	assert_int(parser.call_count).is_equal(1) # 失效本身不查询

	# 仍能按原 spec 重新查询（而不是像修此问题前那样永远返回空容器）
	parser.result = [5, 6]
	assert_array(e.lazy_get("items")).contains_exactly([5, 6])
	assert_int(parser.call_count).is_equal(2)


## 测试: 登记信息未丢 —— 整体失效后仍能按同一 select 重新查询
func test_invalidate_all_preserves_select_name() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_by_parent", [42]))
	e.lazy_get("items")

	e.invalidate_lazy()
	e.lazy_get("items")

	assert_int(parser.call_count).is_equal(2)
	assert_str(parser.last_select).is_equal("select_by_parent")
	assert_array(parser.last_args).contains_exactly([42])


## 测试: 对没有登记过 spec 的属性调用 invalidate_lazy 不会破坏后续行为
func test_invalidate_unknown_property_is_harmless() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))

	e.invalidate_lazy("child") # child 从未登记

	assert_bool(e.is_lazy_loaded("items")).is_false()
	assert_int(parser.call_count).is_equal(0)


## 测试: 显式赋值（lazy_set / 属性 setter）后不再触发懒查询
func test_lazy_set_marks_loaded_and_skips_fetch() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))

	e.lazy_set("items", [9, 8])

	assert_bool(e.is_lazy_loaded("items")).is_true()
	assert_array(e.lazy_get("items")).contains_exactly([9, 8])
	assert_int(parser.call_count).is_equal(0)


## 测试: is_lazy_loaded 自身绝不触发查询（动态 SQL 的 <if test> 依赖这个性质）
func test_is_lazy_loaded_does_not_trigger_fetch() -> void:
	var parser := _RecordingParser.new()
	var e = _make_entity(SOURCE_BASIC)
	e.set_lazy_spec("items", _collection_spec(parser, "select_items", []))

	e.is_lazy_loaded("items")
	e.is_lazy_loaded("items")

	assert_int(parser.call_count).is_equal(0)


# --------------------------------------------------------------------------
# Real typed array element resolution (Array[SomeEntity])
# --------------------------------------------------------------------------

## 测试: 未登记懒加载时，Array[SomeEntity] 属性返回按元素类构造的 typed 数组
func test_typed_default_for_entity_element_type() -> void:
	var child_script := _make_script(SOURCE_CHILD)
	assert_object(child_script).is_not_null()

	# 父类脚本的元素类型必须是一个**真实存在的全局类**，
	# 否则 Array[X] 会退化成不带元素类型的数组。
	var parent_source := """extends GDSQL.GBatisEntity
var id = GDSQL.GBatisEntity.NULL
var children: Array[RefCounted]
"""
	var parent_script := _make_script(parent_source)
	assert_object(parent_script).is_not_null()

	var e = parent_script.new()
	var ret = e.lazy_get("children")

	assert_array(ret).is_not_null()
	assert_array(ret).is_empty()
	assert_bool((ret as Array).is_typed()).is_true()


## 测试: 元素类型为内建类型时同样返回 typed 空数组
func test_typed_default_for_builtin_element_type() -> void:
	var e = _make_entity("""extends GDSQL.GBatisEntity
var nums: Array[int]
""")

	var ret = e.lazy_get("nums")

	assert_array(ret).is_not_null()
	assert_array(ret).is_empty()
	assert_bool((ret as Array).is_typed()).is_true()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## 一个可编程的 GBatisMapper 替身：记录 call_method_in_namespace 的调用。
class _RecordingParser:
	extends RefCounted

	var call_count := 0
	var last_select := ""
	var last_args: Array = []
	var result: Variant = []

	func call_method_in_namespace(method: String, args: Array) -> Variant:
		call_count += 1
		last_select = method
		last_args = args
		return result


func _make_script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	@warning_ignore("return_value_discarded")
	script.reload()
	return script


func _make_entity(source: String):
	return _make_script(source).new()


## 默认原型用 Array[int]，与 SOURCE_BASIC 的 `items: Array[int]` 元素类型一致，
## 这样其它用例只验证懒加载语义，不会被容器类型转换干扰。
func _collection_spec(parser, select_name: String, args: Array) -> Dictionary:
	return {
		"parser": weakref(parser),
		"select": select_name,
		"args": args,
		"typed_proto": Array([], TYPE_INT, "", null),
	}


func _association_spec(parser, select_name: String) -> Dictionary:
	return {
		"parser": weakref(parser),
		"select": select_name,
		"args": [],
		"typed_proto": null,
	}
