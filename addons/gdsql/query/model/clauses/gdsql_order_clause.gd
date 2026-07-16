class_name GDSQLOrderClause
extends RefCounted

enum SortDirection { ASCENDING, DESCENDING }

var expression: GDSQLQueryExpression
var direction: SortDirection = SortDirection.ASCENDING
