class_name GDSQLBoundQuery
extends RefCounted

var source_query: GDSQLQuerySpec
var root_operation: GDSQLBoundQueryOperation
var referenced_tables: Array[GDSQLTableDefinition] = []
var output_schema: GDSQLResultSchema
