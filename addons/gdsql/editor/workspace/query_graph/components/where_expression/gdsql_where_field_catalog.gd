class_name GDSQLEditorWhereFieldCatalog
extends RefCounted
## Builds the bounded field list presented by the shared WHERE editor.

var _resource_properties: GDSQLResourcePropertyCatalog


func _init(resource_properties: GDSQLResourcePropertyCatalog = null) -> void:
	_resource_properties = (
			resource_properties
			if resource_properties != null
			else GDSQLResourcePropertyCatalog.new()
	)


func build(columns: Array[GDSQLColumnDefinition]) -> Array[GDSQLEditorWhereField]:
	var fields: Array[GDSQLEditorWhereField] = []
	for column in columns:
		if column.data_type != TYPE_OBJECT:
			fields.append(
				GDSQLEditorWhereField.new(
					column.name,
					[],
					column.data_type,
					column.nullable,
				),
			)
			continue
		for property in _resource_properties.list_filterable_leaves(column.resource_type):
			fields.append(
				GDSQLEditorWhereField.new(
					column.name,
					property.path,
					property.data_type,
					true,
				),
			)
	return fields
