@abstract
class_name GDSQLQuerySpec
extends RefCounted

enum Operation { SELECT, INSERT, UPDATE, DELETE }

var operation: Operation


@abstract
func accept(visitor: GDSQLQuerySpecVisitor) -> Variant
