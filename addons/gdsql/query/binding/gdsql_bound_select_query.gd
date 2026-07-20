class_name GDSQLBoundSelectQuery
extends GDSQLBoundQueryOperation

var source: GDSQLBoundTableSource
var joins: Array[GDSQLBoundJoin] = []
var projections: Array[GDSQLSelectProjection] = []
var predicate: GDSQLQueryExpression
var grouping: Array[GDSQLQueryExpression] = []
var having: GDSQLQueryExpression
var ordering: Array[GDSQLOrderClause] = []
var limit: int = -1
var offset: int = 0
var distinct: bool = false
