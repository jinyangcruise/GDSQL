extends GDSQL.GBatisEntity
class_name GDSQLTestChildEntity

## 测试用实体（配合 GDSQLTestParentEntity / test_gdsql_utils 使用）。
## 必须带 class_name：`[] as Array[X]` 要求 X 是已注册的全局类，
## 这也是 GDSQL.GBatisEntityDB.get_class_path() 查找类路径的依据。

var id = GDSQL.GBatisEntity.NULL
var note = GDSQL.GBatisEntity.NULL
