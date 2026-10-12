extends RefCounted
## Narrow lifecycle bridge for Godot-AI's no-argument lazy tool handlers.

static var _inspection_service: WeakRef
static var _authoring_service: WeakRef


static func attach(
		inspection_service: GDSQLMcpInspectionService,
		authoring_service: GDSQLMcpAuthoringService = null,
) -> void:
	_inspection_service = weakref(inspection_service) if inspection_service != null else null
	_authoring_service = weakref(authoring_service) if authoring_service != null else null


static func detach(
		inspection_service: GDSQLMcpInspectionService,
		authoring_service: GDSQLMcpAuthoringService = null,
) -> void:
	if get_inspection_service() == inspection_service:
		_inspection_service = null
	if get_authoring_service() == authoring_service:
		_authoring_service = null


static func get_service() -> GDSQLMcpInspectionService:
	return get_inspection_service()


static func get_inspection_service() -> GDSQLMcpInspectionService:
	return (
			_inspection_service.get_ref() as GDSQLMcpInspectionService
			if _inspection_service != null
			else null
	)


static func get_authoring_service() -> GDSQLMcpAuthoringService:
	return (
			_authoring_service.get_ref() as GDSQLMcpAuthoringService
			if _authoring_service != null
			else null
	)
