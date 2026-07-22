@abstract
class_name GDSQLModel
extends RefCounted
## Base for a materialized row associated with a logical database role.
##
## Subclasses declare model metadata through overridable methods. A
## [GDSQLModelRegistry] captures that metadata and a [GDSQLModelContext]
## resolves the role to an active database. Physical storage remains outside
## the model layer.

var _model_context: GDSQLModelContext
var _persisted := false
var _original_values: Dictionary[StringName, Variant] = { }
var _loaded_relationships: Dictionary[StringName, Variant] = { }


## Declares the logical database role used by this model.
func database_role() -> StringName:
	return &""


## Declares the logical table represented by this model.
@abstract
func table_name() -> StringName


## Declares the column used as model identity.
func primary_key() -> StringName:
	return &"id"


## Declares whether canonical mutation helpers may be exposed for this model.
func access_mode() -> GDSQLModelAccess.Mode:
	return GDSQLModelAccess.Mode.READ_ONLY


## Declares named relationships captured during model registration.
func relationships() -> Array[GDSQLRelationshipDefinition]:
	return []


## Returns the context retained during model materialization.
func get_model_context() -> GDSQLModelContext:
	return _model_context


## Reports whether this object was materialized from a persisted row.
func is_persisted() -> bool:
	return _persisted


## Reports whether an explicit or eager relationship load has completed.
func is_relationship_loaded(relationship_name: StringName) -> bool:
	return _loaded_relationships.has(relationship_name)


## Returns a loaded model, model array, or null for the named relationship.
func get_related(relationship_name: StringName) -> Variant:
	return _loaded_relationships.get(relationship_name)


## Persists changed fields through a canonical UPDATE operation.
func save() -> GDSQLQueryResult:
	var readiness := _resolve_mutation()
	if not readiness.is_successful():
		return readiness
	var definition := readiness.get_value()[&"definition"] as GDSQLModelDefinition
	var database := readiness.get_value()[&"database"] as GDSQLDatabase
	var identity: Variant = _original_values.get(definition.primary_key)
	if get(definition.primary_key) != identity:
		return _failure(
			&"GDSQL_MODEL_PRIMARY_KEY_IMMUTABLE",
			"A persisted model's primary key cannot be changed.",
		)
	var builder := database.table(definition.table_name).update()
	var changed_columns := 0
	for column_name in _original_values:
		if column_name == definition.primary_key:
			continue
		var current_value: Variant = get(column_name)
		if current_value != _original_values[column_name]:
			builder.set_value(column_name, current_value)
			changed_columns += 1
	if changed_columns == 0:
		var unchanged := GDSQLQueryResult.new()
		unchanged.value = self
		unchanged.statistics = { "affected_rows": 0 }
		return unchanged
	builder.where(GDSQLExpr.column(definition.primary_key).equals(identity))
	var result := database.execute(builder.build())
	if result.is_successful() and not result.rows.is_empty():
		_apply_row(result.rows[0])
		result.value = self
	return result


## Reloads this model's current row into the same object.
func refresh() -> GDSQLQueryResult:
	var readiness := _resolve_persisted()
	if not readiness.is_successful():
		return readiness
	var definition := readiness.get_value()[&"definition"] as GDSQLModelDefinition
	var identity: Variant = _original_values.get(definition.primary_key)
	var result := _model_context.find(get_script(), identity)
	if not result.is_successful():
		return result
	var refreshed := result.get_value() as GDSQLModel
	if refreshed == null:
		return _failure(
			&"GDSQL_MODEL_ROW_NOT_FOUND",
			"The persisted model row was not found during refresh.",
		)
	_apply_values(refreshed._original_values)
	result.value = self
	return result


## Deletes this model's row through a canonical DELETE operation.
func delete() -> GDSQLQueryResult:
	var readiness := _resolve_mutation()
	if not readiness.is_successful():
		return readiness
	var definition := readiness.get_value()[&"definition"] as GDSQLModelDefinition
	var database := readiness.get_value()[&"database"] as GDSQLDatabase
	var identity: Variant = _original_values.get(definition.primary_key)
	var result := database.execute(
		database.table(definition.table_name)
		.delete()
		.where(GDSQLExpr.column(definition.primary_key).equals(identity))
		.build(),
	)
	if result.is_successful() and result.get_affected_rows() > 0:
		_persisted = false
		result.value = self
	return result


func _attach_model_context(
		context: GDSQLModelContext,
		persisted: bool,
		values: Dictionary[StringName, Variant] = { },
) -> void:
	_model_context = context
	_persisted = persisted
	_original_values = values.duplicate()
	_loaded_relationships.clear()


func _set_loaded_relationship(relationship_name: StringName, value: Variant) -> void:
	_loaded_relationships[relationship_name] = value


func _resolve_persisted() -> GDSQLQueryResult:
	if _model_context == null:
		return _failure(
			&"GDSQL_MODEL_CONTEXT_REQUIRED",
			"A materialized model context is required.",
		)
	if not _persisted:
		return _failure(
			&"GDSQL_MODEL_NOT_PERSISTED",
			"This model does not represent a persisted row.",
		)
	var definition_result := _model_context.resolve_model(get_script())
	if not definition_result.is_successful():
		return _failure_from(definition_result)
	var result := GDSQLQueryResult.new()
	result.value = { &"definition": definition_result.get_value() }
	return result


func _resolve_mutation() -> GDSQLQueryResult:
	var result := _resolve_persisted()
	if not result.is_successful():
		return result
	var definition := result.get_value()[&"definition"] as GDSQLModelDefinition
	if definition.access_mode != GDSQLModelAccess.Mode.READ_WRITE:
		return _failure(
			&"GDSQL_MODEL_READ_ONLY",
			"This model type permits read operations only.",
		)
	var database_result := _model_context.resolve_database(get_script())
	if not database_result.is_successful():
		return _failure_from(database_result)
	result.value[&"database"] = database_result.get_database()
	return result


func _apply_row(row: GDSQLRowRecord) -> void:
	var values: Dictionary[StringName, Variant] = { }
	for column_name: StringName in row.values:
		if _has_property(column_name):
			values[column_name] = row.get_value(column_name)
	_apply_values(values)


func _apply_values(values: Dictionary[StringName, Variant]) -> void:
	for property_name in values:
		if _has_property(property_name):
			set(property_name, values[property_name])
	_original_values = values.duplicate()
	_persisted = true
	_loaded_relationships.clear()


func _has_property(property_name: StringName) -> bool:
	for property in get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _failure_from(source: GDSQLOperationResult) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.diagnostics.merge(source.diagnostics)
	return result


func _failure(code: StringName, message: String) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
