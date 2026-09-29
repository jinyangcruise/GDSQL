@tool
class_name GDSQLEditorContentReference
extends RefCounted
## Editor metadata for one ownership-neutral save-to-content identifier.

var relationship_name: StringName
var source_registration_name: StringName
var source_database_name: StringName
var source_table_name: StringName
var source_column_name: StringName
var target_registration_name: StringName
var target_database_name: StringName
var target_table_name: StringName
var target_column_name: StringName
var target_model_class: StringName


func _init(
		reference_name: StringName = &"",
		source_registration: StringName = &"",
		source_database: StringName = &"",
		source_table: StringName = &"",
		source_column: StringName = &"",
		target_registration: StringName = &"",
		target_database: StringName = &"",
		target_table: StringName = &"",
		target_column: StringName = &"",
		target_class: StringName = &"",
) -> void:
	relationship_name = reference_name
	source_registration_name = source_registration
	source_database_name = source_database
	source_table_name = source_table
	source_column_name = source_column
	target_registration_name = target_registration
	target_database_name = target_database
	target_table_name = target_table
	target_column_name = target_column
	target_model_class = target_class


func is_valid() -> bool:
	return relationship_name != &"" \
			and source_registration_name != &"" \
			and source_database_name != &"" \
			and source_table_name != &"" \
			and source_column_name != &"" \
			and target_registration_name != &"" \
			and target_database_name != &"" \
			and target_table_name != &"" \
			and target_column_name != &""


func build_relationship_snippet() -> String:
	if not is_valid() or target_model_class == &"":
		return ""
	return "\n".join(
		[
			"GDSQLRelationshipDefinition.references_one(",
			"\t&\"%s\"," % String(relationship_name).c_escape(),
			"\t%s," % target_model_class,
			"\t&\"%s\"," % source_column_name,
			"\t&\"%s\"," % target_column_name,
			"),",
		],
	)
