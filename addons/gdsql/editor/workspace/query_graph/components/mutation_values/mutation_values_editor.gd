@tool
class_name GDSQLMutationValuesEditor
extends VBoxContainer
## Shared typed value list for one INSERT row or UPDATE assignments.

signal changed

enum Mode {
	INSERT,
	UPDATE,
}

const VALUE_ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/components/mutation_values/mutation_value_row.tscn"
)

@export var mode := Mode.INSERT

@onready var _rows: VBoxContainer = %Rows
@onready var _empty_status: Label = %EmptyStatus


func configure(
		columns: Array[GDSQLColumnDefinition],
		excluded_columns: Array[StringName] = [],
) -> void:
	_clear_rows()
	for column in columns:
		var row := VALUE_ROW_SCENE.instantiate() as GDSQLMutationValueRow
		_rows.add_child(row)
		row.changed.connect(changed.emit)
		row.configure(
			column,
			mode == Mode.INSERT,
			column.name not in excluded_columns,
		)
	_empty_status.visible = columns.is_empty()
	changed.emit()


func build_values() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var values: Dictionary = { }
	for row in _get_rows():
		if not row.is_included():
			continue
		var value_result := row.get_value_result()
		if not bool(value_result.get("valid", false)):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_QUERY_GRAPH_MUTATION_VALUE_INVALID",
					"Column '%s' does not contain a valid typed value."
					% row.get_column_name(),
				),
			)
			return result
		values[row.get_column_name()] = value_result.get("value")
	if values.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_MUTATION_VALUE_REQUIRED",
				"Select at least one column value.",
			),
		)
		return result
	result.value = values
	return result


func get_included_count() -> int:
	var count := 0
	for row in _get_rows():
		if row.is_included():
			count += 1
	return count


func _clear_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


func _get_rows() -> Array[GDSQLMutationValueRow]:
	var rows: Array[GDSQLMutationValueRow] = []
	for child in _rows.get_children():
		if child is GDSQLMutationValueRow:
			rows.append(child)
	return rows
