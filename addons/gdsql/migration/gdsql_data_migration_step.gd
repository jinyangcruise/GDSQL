class_name GDSQLDataMigrationStep
extends GDSQLMigrationStep
## One deterministic canonical UPDATE against a single table.

const ExpressionCodec = preload(
	"res://addons/gdsql/migration/gdsql_migration_expression_codec.gd"
)

var assignments: Array[GDSQLColumnAssignment] = []
var predicate: GDSQLQueryExpression


func _init(
		target_table: StringName = &"",
		requested_assignments: Array[GDSQLColumnAssignment] = [],
		row_predicate: GDSQLQueryExpression = null,
) -> void:
	table_name = target_table
	assignments = requested_assignments.duplicate()
	predicate = row_predicate


func is_valid() -> bool:
	if table_name == &"" or not String(table_name).is_valid_identifier() \
			or assignments.is_empty():
		return false
	var assigned_columns: Dictionary[StringName, bool] = { }
	for assignment in assignments:
		if assignment == null or assignment.column == &"" \
				or not String(assignment.column).is_valid_identifier() \
				or assigned_columns.has(assignment.column) \
				or ExpressionCodec.encode(assignment.expression).is_empty():
			return false
		assigned_columns[assignment.column] = true
	return predicate == null or not ExpressionCodec.encode(predicate).is_empty()


func is_destructive() -> bool:
	return true


func to_query(database_name: StringName) -> GDSQLUpdateQuerySpec:
	var query := GDSQLUpdateQuerySpec.new()
	query.target = GDSQLTableReference.new(table_name, database_name)
	query.assignments = assignments.duplicate()
	query.predicate = predicate
	return query
