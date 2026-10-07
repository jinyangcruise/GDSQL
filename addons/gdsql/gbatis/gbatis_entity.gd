extends RefCounted

signal value_changed(property, new_val)

static var NULL = RefCounted.new()

## —— 懒加载（resultMap 里 <association>/<collection> 的 fetchType="lazy"）——
##
## 实体侧每个惰性字段写两行（值统一存在 _lazy_values 里，无需额外 backing 字段）：
##     var arr_t_hero: Array[THeroEntity]:
##         get: return lazy_get("arr_t_hero")
##         set(value): lazy_set("arr_t_hero", value)
## mapper 侧：遇到 fetchType="lazy" 的关联/集合时不查询，改调 set_lazy_spec() 登记"怎么取"。
var _lazy_specs := { } # property -> {parser: WeakRef, select: String, args: Array, typed_proto: Array}
var _lazy_values := { } # property -> 值（已加载或已显式赋值）
var _lazy_loaded := { } # property -> bool


func is_all_propeties_set() -> bool:
	for i in (get_script() as GDScript).get_script_property_list():
		if i.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if is_same(get_indexed(i.name), NULL):
				return false
	return true


func is_property_set(property) -> bool:
	return not is_same(get_indexed(property), NULL)


func is_properties_set(properties: Array) -> bool:
	for i in properties:
		if is_same(get_indexed(i), NULL):
			return false
	return true


## 由 mapper 调用：登记某个惰性字段"怎么取"，但**不立即查询**。
func set_lazy_spec(property: String, spec: Dictionary) -> void:
	_lazy_specs[property] = spec
	_lazy_values.erase(property)
	_lazy_loaded[property] = false


## 属性 getter 调用：首次访问时才真正执行子查询，之后走缓存。
func lazy_get(property: String) -> Variant:
	if not _lazy_loaded.get(property, false):
		if not _lazy_specs.has(property):
			# 从未登记懒加载（例如刚 new 出来、或该字段本来就是 eager）：返回**空 typed 容器**，
			# 保持"未设置即空集合"的旧语义，避免调用方拿到 null 后 for/in 崩掉。
			return _empty_typed_default(property)
		_lazy_loaded[property] = true
		_lazy_values[property] = _run_lazy_spec(property)
	return _lazy_values.get(property)


## 属性 setter 调用（mapper 显式赋值或业务代码赋值）：标记已加载，不再触发懒查询。
func lazy_set(property: String, value: Variant) -> void:
	_lazy_values[property] = value
	_lazy_loaded[property] = true


## 该惰性字段是否已加载 —— 供 is_property_set() 之类"只想知道有没有值"的场景使用，
## **不会触发**懒加载（否则动态 SQL 的 <if test="x != null"> 会在 update 时凭空发起查询）。
func is_lazy_loaded(property: String) -> bool:
	return _lazy_loaded.get(property, false)


## 丢弃懒加载缓存（写入/删除后调用，避免读到陈旧集合）。不传参数则整体丢弃。
func invalidate_lazy(property: String = "") -> void:
	if property.is_empty():
		_lazy_specs.clear()
		_lazy_values.clear()
		_lazy_loaded.clear()
		return
	_lazy_loaded[property] = false
	_lazy_values.erase(property)


## 按属性声明的元素类型造一个空 typed 数组（非数组属性返回 null）。
## 构造法与 result_map.gd 的 _gen_array() 一致：Array([], TYPE_OBJECT, 基类, 脚本)。
func _empty_typed_default(property: String) -> Variant:
	var of_type := ""
	for p in (get_script() as GDScript).get_script_property_list():
		if p.name == property:
			if p.hint == PROPERTY_HINT_ARRAY_TYPE:
				of_type = p.hint_string
			break
	if of_type.is_empty():
		return null
	if GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.has(of_type):
		return Array([], GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES[of_type], "", null)
	if ClassDB.class_exists(of_type):
		return Array([], TYPE_OBJECT, of_type, null)
	var script = load(GDSQL.GBatisEntityDB.get_class_path(of_type))
	var base = GDSQL.GBatisEntityDB.get_class_base(of_type)
	if base == "" or not ClassDB.class_exists(base):
		var obj: Object = script.new()
		base = obj.get_class()
		if not obj is RefCounted:
			obj.free()
	return Array([], TYPE_OBJECT, base, script)


func _run_lazy_spec(property: String) -> Variant:
	var spec: Dictionary = _lazy_specs.get(property, { })
	var parser_ref: WeakRef = spec.get("parser")
	var select_name := String(spec.get("select", ""))
	if parser_ref == null or parser_ref.get_ref() == null or select_name.is_empty():
		push_warning("GBatis: 懒加载 %s 失败（mapper/select 不可用），返回空值。" % property)
		return null
	var result = parser_ref.get_ref().call_method_in_namespace(select_name, spec.get("args", []))
	# 与 eager 路径保持一致的容器类型：集合用注册时生成的 typed 空数组当原型
	var proto = spec.get("typed_proto")
	if proto is Array and result is Array and not (result as Array).is_empty():
		var typed: Array = (proto as Array).duplicate()
		typed.assign(result)
		return typed
	return result
