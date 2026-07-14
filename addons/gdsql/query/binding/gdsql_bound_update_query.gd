class_name GDSQLBoundUpdateQuery
extends GDSQLBoundQueryOperation

var target: GDSQLTableDefinition
var assignments: Array[GDSQLColumnAssignment] = []
var predicate: GDSQLQueryExpression
