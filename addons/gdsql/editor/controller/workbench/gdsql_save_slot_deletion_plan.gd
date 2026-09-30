class_name GDSQLSaveSlotDeletionPlan
extends RefCounted
## Validated editor intent for deleting one standard save-slot database.
##
## This plan does not delete files. It narrows the destructive target to one
## registered database whose data root is a direct child of the standard save
## directory.

const STANDARD_SAVE_SLOTS_ROOT := "user://gdsql/saves"

var registration_name: StringName
var database_name: StringName
var data_root: String
var database_path: String
var was_active := false
var fallback_registration_name: StringName


static func build(
		registration: GDSQLDatabaseRegistration,
		active_registration_name: StringName = &"",
		available_registrations: Array[GDSQLDatabaseRegistration] = [],
) -> GDSQLOperationResult:
	if registration == null:
		return _error(
			&"GDSQL_SAVE_SLOT_REGISTRATION_REQUIRED",
			"Select a registered save slot before deleting its data.",
		)
	if registration.name == &"" or registration.database_name == &"":
		return _error(
			&"GDSQL_SAVE_SLOT_REGISTRATION_INVALID",
			"The selected save slot requires registration and database names.",
		)
	var normalized_root := registration.data_root.strip_edges().simplify_path().trim_suffix("/")
	var standard_root := STANDARD_SAVE_SLOTS_ROOT.simplify_path().trim_suffix("/")
	if normalized_root == standard_root or normalized_root.get_base_dir() != standard_root:
		return _error(
			&"GDSQL_SAVE_SLOT_DELETE_ROOT_REJECTED",
			(
					"Only a database in a direct child of '%s' can be deleted as a save slot. "
					+ "The selected root is '%s'."
			)
			% [STANDARD_SAVE_SLOTS_ROOT, registration.data_root],
		)
	var plan := GDSQLSaveSlotDeletionPlan.new()
	plan.registration_name = registration.name
	plan.database_name = registration.database_name
	plan.data_root = normalized_root
	plan.database_path = normalized_root.path_join(String(registration.database_name))
	plan.was_active = registration.name == active_registration_name
	if plan.was_active:
		plan.fallback_registration_name = _find_fallback(
			registration,
			available_registrations,
		)
	var result := GDSQLOperationResult.new()
	result.value = plan
	return result


static func _find_fallback(
		removed: GDSQLDatabaseRegistration,
		available: Array[GDSQLDatabaseRegistration],
) -> StringName:
	var candidates: Array[GDSQLDatabaseRegistration] = []
	var standard_root := STANDARD_SAVE_SLOTS_ROOT.simplify_path().trim_suffix("/")
	for candidate in available:
		if candidate == null or candidate.name == removed.name \
				or candidate.database_name != removed.database_name \
				or candidate.migration_stream != removed.migration_stream:
			continue
		var candidate_root := candidate.data_root.strip_edges().simplify_path() \
				.trim_suffix("/")
		if candidate_root.get_base_dir() == standard_root:
			candidates.append(candidate)
	candidates.sort_custom(
		func(
				left: GDSQLDatabaseRegistration,
				right: GDSQLDatabaseRegistration,
		) -> bool:
			return String(left.name).naturalnocasecmp_to(String(right.name)) < 0,
	)
	return candidates[0].name if not candidates.is_empty() else &""


static func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
