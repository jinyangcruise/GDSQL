class_name GDSQLResourceLoadProgress
extends RefCounted
## Backend-neutral snapshot of one asynchronous Resource load.

enum Status { IN_PROGRESS, LOADED }

var status := Status.IN_PROGRESS
var progress: float
var resource: Resource


static func in_progress(value: float) -> GDSQLResourceLoadProgress:
	var snapshot := GDSQLResourceLoadProgress.new()
	snapshot.progress = clampf(value, 0.0, 1.0)
	return snapshot


static func loaded(value: Resource) -> GDSQLResourceLoadProgress:
	var snapshot := GDSQLResourceLoadProgress.new()
	snapshot.status = Status.LOADED
	snapshot.progress = 1.0
	snapshot.resource = value
	return snapshot


func is_complete() -> bool:
	return status == Status.LOADED
