class_name GDSQLMcpMutationTicket
extends RefCounted
## One-use editor-memory authority for one previewed MCP row mutation.

enum Operation { INSERT, UPDATE, DELETE }

var token: String
var operation: Operation
var registration_name: StringName
var table_name: StringName
var payload: Dictionary
var schema_fingerprint: String
var row_fingerprint: String
var expires_at_msec: int


func is_expired(now_msec: int = Time.get_ticks_msec()) -> bool:
	return now_msec >= expires_at_msec
