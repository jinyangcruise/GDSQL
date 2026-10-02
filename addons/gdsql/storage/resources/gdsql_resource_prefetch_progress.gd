class_name GDSQLResourcePrefetchProgress
extends RefCounted
## Aggregate snapshot for one bounded Resource prefetch scope.

enum Status { IN_PROGRESS, LOADED, FAILED }

var status := Status.IN_PROGRESS
var progress: float
var total_count: int
var loaded_count: int
var failed_count: int


func is_complete() -> bool:
	return loaded_count + failed_count >= total_count


func is_successful() -> bool:
	return is_complete() and failed_count == 0

