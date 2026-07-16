class_name GDSQLBoundSelectQuery
extends GDSQLBoundQueryOperation

var source: GDSQLTableDefinition
var projections: Array[GDSQLQueryExpression] = []
var predicate: GDSQLQueryExpression
var limit: int = -1
var offset: int = 0
