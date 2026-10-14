class_name GDSQLMcpDatabaseMutationTicket
extends RefCounted
## One short-lived, one-use preview for a registered database lifecycle change.

var token := ""
var operation := ""
var payload: Dictionary = { }
var workspace_fingerprint := ""
var expires_at_msec := 0


func is_expired() -> bool:
	return Time.get_ticks_msec() >= expires_at_msec
