class_name GDSQLJoinSpec
extends RefCounted

enum JoinType { INNER, LEFT, RIGHT, FULL }

var type: JoinType
var source: GDSQLQuerySource
var condition: GDSQLQueryExpression
