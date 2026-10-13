class_name GDSQLMcpModelMutationTicket
extends RefCounted
## One expiring model-source or cross-role reference preview.

var token := ""
var operation := ""
var payload: Dictionary = { }
var fingerprint := ""
var expires_at_msec := 0


func is_expired() -> bool:
	return Time.get_ticks_msec() >= expires_at_msec
