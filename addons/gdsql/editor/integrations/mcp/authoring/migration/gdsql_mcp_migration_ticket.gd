class_name GDSQLMcpMigrationTicket
extends RefCounted
## One expiring migration preview shared by authoring and pending application.

var token := ""
var registration_name: StringName
var definition: GDSQLMigrationDefinition
var expected_history_count := 0
var definition_persisted := false
var plan_fingerprint := ""
var expires_at_msec := 0


func is_expired() -> bool:
	return Time.get_ticks_msec() >= expires_at_msec
