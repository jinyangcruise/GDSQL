class_name GDSQLContentRowOperation
extends RefCounted
## One typed row change supplied by an immutable content package layer.

enum Kind {
	UPSERT,
	REMOVE,
}

var kind: Kind
var table_name: StringName
var identity: Variant
var row: GDSQLRowRecord


static func upsert(
		table: StringName,
		row_identity: Variant,
		row_record: GDSQLRowRecord,
) -> GDSQLContentRowOperation:
	return GDSQLContentRowOperation.new(Kind.UPSERT, table, row_identity, row_record)


static func remove(
		table: StringName,
		row_identity: Variant,
) -> GDSQLContentRowOperation:
	return GDSQLContentRowOperation.new(Kind.REMOVE, table, row_identity)


func _init(
		operation_kind: Kind = Kind.UPSERT,
		table: StringName = &"",
		row_identity: Variant = null,
		row_record: GDSQLRowRecord = null,
) -> void:
	kind = operation_kind
	table_name = table
	identity = row_identity
	row = row_record.duplicate_record() if row_record != null else null
