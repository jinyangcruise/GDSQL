class_name GDSQLStorageReadStatistics
extends RefCounted
## Backend-reported work for one bounded read. Unknown physical measurements
## remain -1 rather than being presented as zero work.

var rows_scanned: int
var rows_returned: int
var bytes_read := -1
var pages_read := -1
var physical_read_bounded := false


func duplicate_statistics() -> GDSQLStorageReadStatistics:
	var statistics := GDSQLStorageReadStatistics.new()
	statistics.rows_scanned = rows_scanned
	statistics.rows_returned = rows_returned
	statistics.bytes_read = bytes_read
	statistics.pages_read = pages_read
	statistics.physical_read_bounded = physical_read_bounded
	return statistics
