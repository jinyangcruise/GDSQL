extends RefCounted
## Narrow lifecycle bridge for Godot-AI's no-argument lazy tool handlers.

static var _service: WeakRef


static func attach(service: GDSQLMcpInspectionService) -> void:
	_service = weakref(service) if service != null else null


static func detach(service: GDSQLMcpInspectionService) -> void:
	if get_service() == service:
		_service = null


static func get_service() -> GDSQLMcpInspectionService:
	return _service.get_ref() as GDSQLMcpInspectionService if _service != null else null
