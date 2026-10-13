extends SceneTree

const DATABASE_NAME := &"benchmark"
const TABLE_NAME := &"records"
const INSERT_BATCH_SIZE := 1000
const WINDOW_SIZE := 50
const FILTER_LIMIT := 100
const REPORT_VERSION := 1

var _report: Dictionary = { }
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var benchmark_started := Time.get_ticks_usec()
	var row_counts := _parse_row_counts(
		OS.get_environment("GDSQL_BENCHMARK_ROWS"),
	)
	var iterations := maxi(
		1,
		int(OS.get_environment("GDSQL_BENCHMARK_ITERATIONS")),
	)
	var data_root := OS.get_environment("GDSQL_BENCHMARK_DATA_ROOT")
	var report_directory := OS.get_environment("GDSQL_BENCHMARK_REPORT_DIR")
	if row_counts.is_empty() or data_root.is_empty() or report_directory.is_empty():
		_fail(
			"Benchmark requires GDSQL_BENCHMARK_ROWS, " \
					+ "GDSQL_BENCHMARK_DATA_ROOT, and GDSQL_BENCHMARK_REPORT_DIR.",
		)
		quit(1)
		return

	_report = {
		"format": "gdsql-configfile-benchmark",
		"format_version": REPORT_VERSION,
		"generated_at_utc": Time.get_datetime_string_from_system(true, true),
		"environment": _environment_details(),
		"configuration": {
			"profile": OS.get_environment("GDSQL_BENCHMARK_PROFILE"),
			"row_counts": row_counts,
			"iterations": iterations,
			"insert_batch_size": INSERT_BATCH_SIZE,
			"window_size": WINDOW_SIZE,
			"dataset_seed": "deterministic-formula-v1",
			"storage_backend": "config_file",
		},
		"write_probes": [],
		"datasets": [],
		"notes": [
			"Timing is report-only; this harness does not enforce budgets.",
			"Large read fixtures are seeded directly in the current ConfigFile format and reopened before measurement.",
			"The 1,000-row insert probe uses the public query API and measures its complete staged commit.",
			"Cold cases invalidate GDSQL's ConfigFile cache before every sample.",
			"File bytes describe final table size, not cumulative bytes written.",
		],
	}
	print("Running the 1,000-row public insert probe...")
	(_report["write_probes"] as Array).append(
		_run_insert_probe(data_root.path_join("write_probe"), 1000),
	)

	if not _failed:
		for row_count in row_counts:
			print("Preparing the %d-row ConfigFile dataset..." % row_count)
			var dataset_root := data_root.path_join("rows_%d" % row_count)
			var dataset := _run_dataset(row_count, dataset_root, iterations)
			(_report["datasets"] as Array).append(dataset)
			if _failed:
				break

	_report["successful"] = not _failed
	_report["total_elapsed_usec"] = Time.get_ticks_usec() - benchmark_started
	if not _write_reports(report_directory):
		_failed = true
	quit(1 if _failed else 0)


func _run_dataset(row_count: int, data_root: String, iterations: int) -> Dictionary:
	var dataset := {
		"row_count": row_count,
		"cases": [],
	}
	var created := GDSQLDatabase.create(DATABASE_NAME, data_root)
	if not created.is_successful():
		return _failed_dataset(dataset, "create_database", created.diagnostics)
	var database := created.get_database()
	var table := _table_definition()
	var table_result := database.create_table(table)
	if not table_result.is_successful():
		return _failed_dataset(dataset, "create_table", table_result.diagnostics)

	var storage := database.context.storage as GDSQLConfigFileTableStorage
	var table_path := storage.path_resolver.resolve_table_path(
		DATABASE_NAME,
		TABLE_NAME,
	)
	var seed_started := Time.get_ticks_usec()
	if not _seed_fixture(storage, table, table_path, row_count):
		_fail("Could not seed the %d-row ConfigFile fixture." % row_count)
		return dataset
	var seed_elapsed := Time.get_ticks_usec() - seed_started
	var table_bytes := _file_size(table_path)
	dataset["table_file_bytes"] = table_bytes
	dataset["fixture_seed"] = "direct_configfile_encoding"
	dataset["fixture_seed_usec"] = seed_elapsed
	print(
		"Prepared %d rows in %s (%s setup)." % [
			row_count,
			_format_bytes(table_bytes),
			_format_duration(seed_elapsed),
		],
	)

	var reopened_case := _measure_reopen(data_root, iterations)
	(dataset["cases"] as Array).append(reopened_case["case"])
	if not reopened_case["successful"]:
		_fail("Reopening the %d-row fixture failed." % row_count)
		return dataset
	database = reopened_case["database"] as GDSQLDatabase
	storage = database.context.storage as GDSQLConfigFileTableStorage
	table = database.context.catalog.get_table(DATABASE_NAME, TABLE_NAME)
	if table == null:
		_fail("Reopened benchmark table is unavailable.")
		return dataset

	var queries := [
		{
			"id": "bounded_scan_middle",
			"query": database.table(TABLE_NAME).select() \
					.columns([&"id", &"name"]) \
					.offset(row_count / 2) \
					.limit(WINDOW_SIZE) \
					.build(),
		},
		{
			"id": "ordered_index_window",
			"query": database.table(TABLE_NAME).select() \
					.columns([&"id", &"score"]) \
					.order_by_column(
						&"score",
						GDSQLOrderClause.SortDirection.DESCENDING,
					) \
					.limit(WINDOW_SIZE) \
					.build(),
		},
		{
			"id": "primary_key_lookup",
			"query": database.table(TABLE_NAME).select() \
					.columns([&"id", &"name"]) \
					.where(GDSQLExpr.column(&"id").equals(row_count / 2)) \
					.build(),
		},
		{
			"id": "secondary_index_lookup",
			"query": database.table(TABLE_NAME).select() \
					.columns([&"id", &"external_key"]) \
					.where(
						GDSQLExpr.column(&"external_key").equals(
							_key_for(row_count / 2),
						),
					) \
					.build(),
		},
		{
			"id": "filtered_ordering",
			"query": database.table(TABLE_NAME).select() \
					.columns([&"id", &"score", &"category"]) \
					.where(GDSQLExpr.column(&"category").equals(16)) \
					.order_by_column(
						&"score",
						GDSQLOrderClause.SortDirection.DESCENDING,
					) \
					.limit(FILTER_LIMIT) \
					.build(),
		},
		{
			"id": "full_count",
			"query": database.table(TABLE_NAME).select() \
					.count(null, &"row_count") \
					.build(),
		},
	]
	for query_case in queries:
		print("Measuring %s (cold/warm)..." % query_case["id"])
		(dataset["cases"] as Array).append(
			_measure_query(
				database,
				storage,
				table_path,
				query_case["id"],
				query_case["query"],
				"cold",
				iterations,
			),
		)
		(dataset["cases"] as Array).append(
			_measure_query(
				database,
				storage,
				table_path,
				query_case["id"],
				query_case["query"],
				"warm",
				iterations,
			),
		)
		if _failed:
			return dataset

	var update_query := database.table(TABLE_NAME).update() \
			.set_value(&"name", "Updated benchmark record") \
			.where(
				GDSQLExpr.column(&"external_key").equals(
					_key_for(row_count / 2),
				),
			) \
			.build()
	print("Measuring single-row indexed update...")
	(dataset["cases"] as Array).append(
		_measure_mutation(database, "single_indexed_update", update_query, table_path),
	)
	if _failed:
		return dataset
	var delete_query := database.table(TABLE_NAME).delete() \
			.where(
				GDSQLExpr.column(&"external_key").equals(
					_key_for(row_count),
				),
			) \
			.build()
	print("Measuring single-row indexed delete...")
	(dataset["cases"] as Array).append(
		_measure_mutation(database, "single_indexed_delete", delete_query, table_path),
	)
	dataset["final_table_file_bytes"] = _file_size(table_path)
	return dataset


func _run_insert_probe(data_root: String, row_count: int) -> Dictionary:
	var created := GDSQLDatabase.create(DATABASE_NAME, data_root)
	if not created.is_successful():
		_fail("Could not create the public insert benchmark database.")
		return _error_case("batched_insert", "write", created.diagnostics)
	var database := created.get_database()
	var table_result := database.create_table(_table_definition())
	if not table_result.is_successful():
		_fail("Could not create the public insert benchmark table.")
		return _error_case("batched_insert", "write", table_result.diagnostics)
	var started := Time.get_ticks_usec()
	var inserted := 0
	while inserted < row_count:
		var batch_end := mini(inserted + INSERT_BATCH_SIZE, row_count)
		var builder := database.table(TABLE_NAME).insert()
		for row_index in range(inserted, batch_end):
			builder.values(_fixture_row(row_index + 1))
		var insert_result := database.execute(builder.build())
		if not insert_result.is_successful():
			_fail("The public insert benchmark failed.")
			return _error_case("batched_insert", "write", insert_result.diagnostics)
		inserted = batch_end
	return _single_case(
		"batched_insert",
		"write",
		Time.get_ticks_usec() - started,
		row_count,
		{ "batches": ceili(float(row_count) / INSERT_BATCH_SIZE) },
	)


func _seed_fixture(
		storage: GDSQLConfigFileTableStorage,
		table: GDSQLTableDefinition,
		table_path: String,
		row_count: int,
) -> bool:
	var config := storage.config_cache.get_or_load(table_path)
	if config == null:
		return false
	for id in range(1, row_count + 1):
		var values := _fixture_row(id)
		values[&"id"] = id
		var section := str(id)
		for column in table.columns:
			config.set_value(
				section,
				String(column.name),
				storage.codec.encode(values[column.name], column),
			)
	config.set_value(
		GDSQLConfigFileTableStorage.TABLE_METADATA_SECTION,
		"row_count",
		row_count,
	)
	config.set_value(
		GDSQLConfigFileTableStorage.TABLE_METADATA_SECTION,
		"next_auto_increment",
		row_count + 1,
	)
	storage._rebuild_indexes(config, table)
	return storage.config_cache.flush(table_path) == OK


func _measure_reopen(data_root: String, iterations: int) -> Dictionary:
	var samples: Array[int] = []
	var database: GDSQLDatabase
	for _sample in iterations:
		var started := Time.get_ticks_usec()
		var opened := GDSQLDatabase.open(DATABASE_NAME, data_root)
		var elapsed := Time.get_ticks_usec() - started
		if not opened.is_successful():
			return {
				"successful": false,
				"database": null,
				"case": _error_case("database_reopen", "cold", opened.diagnostics),
			}
		database = opened.get_database()
		samples.append(elapsed)
	return {
		"successful": true,
		"database": database,
		"case": _sampled_case("database_reopen", "cold", samples),
	}


func _measure_query(
		database: GDSQLDatabase,
		storage: GDSQLConfigFileTableStorage,
		table_path: String,
		case_id: String,
		query: GDSQLQuerySpec,
		state: String,
		iterations: int,
) -> Dictionary:
	var samples: Array[int] = []
	var last_result: GDSQLQueryResult
	if state == "warm":
		last_result = database.execute(query)
		if not last_result.is_successful():
			_fail("Warm-up failed for '%s'." % case_id)
			return _error_case(case_id, state, last_result.diagnostics)
	for _sample in iterations:
		if state == "cold":
			storage.config_cache.invalidate(table_path)
		var memory_before := OS.get_static_memory_usage()
		var started := Time.get_ticks_usec()
		last_result = database.execute(query)
		var elapsed := Time.get_ticks_usec() - started
		var memory_after := OS.get_static_memory_usage()
		if not last_result.is_successful():
			_fail("Query benchmark failed for '%s' (%s)." % [case_id, state])
			return _error_case(case_id, state, last_result.diagnostics)
		samples.append(elapsed)
		last_result.statistics["benchmark_memory_delta_bytes"] = \
		memory_after - memory_before
	var case := _sampled_case(case_id, state, samples)
	case["returned_rows"] = last_result.get_returned_rows()
	case["query_statistics"] = _json_safe(last_result.statistics)
	case["process_peak_memory_bytes"] = OS.get_static_memory_peak_usage()
	return case


func _measure_mutation(
		database: GDSQLDatabase,
		case_id: String,
		query: GDSQLQuerySpec,
		table_path: String,
) -> Dictionary:
	var memory_before := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	var result := database.execute(query)
	var elapsed := Time.get_ticks_usec() - started
	if not result.is_successful():
		_fail("Mutation benchmark failed for '%s'." % case_id)
		return _error_case(case_id, "write", result.diagnostics)
	return _single_case(
		case_id,
		"write",
		elapsed,
		result.get_affected_rows(),
		{
			"affected_rows": result.get_affected_rows(),
			"memory_delta_bytes": OS.get_static_memory_usage() - memory_before,
			"process_peak_memory_bytes": OS.get_static_memory_peak_usage(),
			"table_file_bytes": _file_size(table_path),
		},
	)


func _table_definition() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(TABLE_NAME, &"id")
	table.add_column(
		GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
	)
	table.add_column(GDSQLColumnDefinition.new(&"external_key", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.new(&"category", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"score", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"active", TYPE_BOOL, false))
	table.add_column(GDSQLColumnDefinition.new(&"payload", TYPE_STRING, false))
	table.add_index(GDSQLIndexDefinition.new(&"records_by_external_key", [&"external_key"], true))
	table.add_index(GDSQLIndexDefinition.new(&"records_by_category", [&"category"]))
	table.add_index(GDSQLIndexDefinition.new(&"records_by_score", [&"score"]))
	return table


func _fixture_row(id: int) -> Dictionary:
	return {
		&"external_key": _key_for(id),
		&"name": "Record %06d" % id,
		&"category": id % 32,
		&"score": (id * 48271) % 1000003,
		&"active": id % 3 != 0,
		&"payload": "fixture-%06d-abcdefghijklmnopqrstuvwxyz-0123456789" % id,
	}


func _key_for(id: int) -> String:
	return "record_%08d" % id


func _single_case(
		case_id: String,
		state: String,
		elapsed_usec: int,
		operation_count: int,
		extra: Dictionary = { },
) -> Dictionary:
	var case := {
		"id": case_id,
		"state": state,
		"samples_usec": [elapsed_usec],
		"median_usec": elapsed_usec,
		"min_usec": elapsed_usec,
		"max_usec": elapsed_usec,
		"operations": operation_count,
		"operations_per_second": _rate(operation_count, elapsed_usec),
	}
	case.merge(extra)
	return case


func _sampled_case(case_id: String, state: String, samples: Array[int]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	return {
		"id": case_id,
		"state": state,
		"samples_usec": samples,
		"median_usec": ordered[ordered.size() / 2],
		"min_usec": ordered[0],
		"max_usec": ordered[ordered.size() - 1],
	}


func _error_case(case_id: String, state: String, diagnostics: Variant) -> Dictionary:
	return {
		"id": case_id,
		"state": state,
		"error": true,
		"diagnostics": _diagnostic_messages(diagnostics),
	}


func _failed_dataset(
		dataset: Dictionary,
		case_id: String,
		diagnostics: Variant,
) -> Dictionary:
	_fail("Dataset setup failed during '%s'." % case_id)
	(dataset["cases"] as Array).append(_error_case(case_id, "setup", diagnostics))
	return dataset


func _write_reports(report_directory: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(report_directory)
	if error != OK:
		push_error("Cannot create benchmark report directory: %s" % report_directory)
		return false
	var json_path := report_directory.path_join("report.json")
	var markdown_path := report_directory.path_join("report.md")
	if not _write_text(json_path, JSON.stringify(_report, "\t", false, true) + "\n"):
		return false
	if not _write_text(markdown_path, _markdown_report()):
		return false
	print("GDSQL_BENCHMARK_REPORT_JSON=%s" % json_path)
	print("GDSQL_BENCHMARK_REPORT_MARKDOWN=%s" % markdown_path)
	return true


func _markdown_report() -> String:
	var lines: Array[String] = [
		"# GDSQL ConfigFile benchmark",
		"",
		"Generated: `%s`  " % _report["generated_at_utc"],
		"Godot: `%s`  " % _report["environment"]["godot_version"],
		"Platform: `%s`  " % _report["environment"]["platform"],
		"Processor: `%s`  " % _report["environment"]["processor"],
		"Iterations: `%d`  " % _report["configuration"]["iterations"],
		"Total duration: `%s`" % _format_duration(_report["total_elapsed_usec"]),
		"",
		"> Report-only evidence. Compare runs on the same machine and build; " \
				+ "no performance budget is enforced.",
		"",
		"## Public write probe",
		"",
	]
	for probe: Dictionary in _report["write_probes"]:
		if probe.get("error", false):
			lines.append("- `%s`: error" % probe["id"])
		else:
			lines.append(
				"- `%s`: %s for %d rows (%0.2f rows/s)" % [
					probe["id"],
					_format_duration(probe["median_usec"]),
					probe["operations"],
					probe["operations_per_second"],
				],
			)
	lines.append("")
	for dataset: Dictionary in _report["datasets"]:
		lines.append("## %d rows" % dataset["row_count"])
		lines.append("")
		lines.append("Table file: `%s`" % _format_bytes(dataset.get("table_file_bytes", -1)))
		lines.append(
			"Fixture setup: `%s` (not a public API measurement)" \
					% _format_duration(dataset.get("fixture_seed_usec", 0)),
		)
		lines.append("")
		lines.append("| Case | State | Median | Min | Max | Returned/Affected | Bytes read |")
		lines.append("|---|---:|---:|---:|---:|---:|---:|")
		for case: Dictionary in dataset["cases"]:
			if case.get("error", false):
				lines.append("| %s | %s | error | — | — | — | — |" % [case["id"], case["state"]])
				continue
			var statistics: Dictionary = case.get("query_statistics", { })
			var affected: Variant = case.get(
				"returned_rows",
				case.get("affected_rows", case.get("operations", "—")),
			)
			lines.append(
				"| %s | %s | %s | %s | %s | %s | %s |" % [
					case["id"],
					case["state"],
					_format_duration(case["median_usec"]),
					_format_duration(case["min_usec"]),
					_format_duration(case["max_usec"]),
					affected,
					_format_bytes(statistics.get("storage_bytes_read", -1)),
				],
			)
		lines.append("")
	lines.append("## Interpretation notes")
	lines.append("")
	for note: String in _report["notes"]:
		lines.append("- %s" % note)
	lines.append("")
	return "\n".join(lines)


func _environment_details() -> Dictionary:
	var memory := OS.get_memory_info()
	return {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"godot_build": Engine.get_version_info().get("build", "unknown"),
		"platform": OS.get_name(),
		"distribution": OS.get_distribution_name(),
		"processor": OS.get_processor_name(),
		"processor_count": OS.get_processor_count(),
		"model": OS.get_model_name(),
		"debug_build": OS.is_debug_build(),
		"physical_memory_bytes": memory.get("physical", -1),
		"command_line": OS.get_cmdline_args(),
	}


func _parse_row_counts(source: String) -> Array[int]:
	var counts: Array[int] = []
	for value in source.split(",", false):
		var count := int(value.strip_edges())
		if count > 0 and not counts.has(count):
			counts.append(count)
	counts.sort()
	return counts


func _diagnostic_messages(diagnostics: Variant) -> Array[String]:
	var messages: Array[String] = []
	if diagnostics == null:
		return messages
	for diagnostic in diagnostics.entries:
		messages.append("%s: %s" % [diagnostic.code, diagnostic.message])
	return messages


func _json_safe(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var converted := { }
		for key: Variant in value:
			converted[str(key)] = _json_safe(value[key])
		return converted
	if value is Array:
		var converted: Array = []
		for entry: Variant in value:
			converted.append(_json_safe(entry))
		return converted
	return value


func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write benchmark report: %s" % path)
		return false
	file.store_string(content)
	return true


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	return -1 if file == null else file.get_length()


func _rate(operation_count: int, elapsed_usec: int) -> float:
	if elapsed_usec <= 0:
		return 0.0
	return float(operation_count) * 1000000.0 / elapsed_usec


func _format_duration(usec: int) -> String:
	if usec < 1000:
		return "%d us" % usec
	if usec < 1000000:
		return "%.2f ms" % (usec / 1000.0)
	return "%.2f s" % (usec / 1000000.0)


func _format_bytes(bytes: int) -> String:
	if bytes < 0:
		return "n/a"
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.2f KiB" % (bytes / 1024.0)
	return "%.2f MiB" % (bytes / (1024.0 * 1024.0))


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
