extends RefCounted
class_name StrToDaoAdapter

## 用于添加全局的可用数据库，便于解析sql命令
static var valid_databases = []

## 执行一个sql字符串命令
static func query(cmd: String):
	# select db1.table1.xxx from db1.table1 table_alias_1
	# left join db2.table2 table_alias_2 on table_alias_1.xx = table_alias_2.yy
	# union all select ____
	# where ___
	# order by db1.table1.mmm desc
	# limit n, m
	# SELECT_SYMBOL selectOption* selectItemList intoClause? fromClause? whereClause? groupByClause? havingClause?
	pass
