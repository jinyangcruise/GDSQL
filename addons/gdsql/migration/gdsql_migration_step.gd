@abstract
class_name GDSQLMigrationStep
extends RefCounted
## One immutable-by-convention operation in an authored migration.

var table_name: StringName


@abstract
func is_valid() -> bool


@abstract
func is_destructive() -> bool
