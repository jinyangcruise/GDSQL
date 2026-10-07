extends GDSQL.GBatisEntity
class_name GDSQLTestParentEntity

## 测试用实体（配合 GDSQLTestChildEntity / test_gdsql_utils 使用）。
## items 带 lazy_get/lazy_set 访问器 —— 这是 fetchType="lazy" 生效的必要写法。

var id = GDSQL.GBatisEntity.NULL

## GDSQLTestChildEntity.
var items: Array[GDSQLTestChildEntity]:
	get: return lazy_get("items")
	set(value): lazy_set("items", value)
