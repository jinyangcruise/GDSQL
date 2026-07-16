class_name GDSQLBoundSelectQuery
extends GDSQLBoundQueryOperation

var source: GDSQLTableDefinition
var projections: Array[GDSQLSelectProjection] = []
var predicate: GDSQLQueryExpression
var ordering: Array[GDSQLOrderClause] = []
var limit: int = -1
var offset: int = 0
var distinct: bool = false
