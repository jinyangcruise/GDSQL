extends RefCounted
## One-use editor-memory authority for one previewed MCP catalog change.

var token: String
var operation: String
var registration_name: StringName
var plan: GDSQLCatalogChangePlan
var expires_at_msec: int


func is_expired(now_msec: int = Time.get_ticks_msec()) -> bool:
	return now_msec >= expires_at_msec
