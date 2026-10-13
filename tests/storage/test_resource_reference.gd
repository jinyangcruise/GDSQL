class_name GDSQLResourceReferenceTest
extends GdUnitTestSuite

const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"


class CountingResolver:
	extends GDSQLResourceResolver

	var calls := 0
	var resolved_resource: Resource


	func _init(resource: Resource) -> void:
		resolved_resource = resource


	func resolve(_reference: GDSQLResourceReference) -> GDSQLOperationResult:
		calls += 1
		var result := GDSQLOperationResult.new()
		result.value = resolved_resource
		return result


class FailingResolver:
	extends GDSQLResourceResolver


	func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_TEST_RESOURCE_FAILED",
				"Forced deferred Resource failure.",
				GDSQLQueryDiagnostic.Severity.ERROR,
				null,
				reference,
			),
		)
		return result


class ThreadedResolver:
	extends CountingResolver

	var requests := 0
	var polls := 0


	func request_threaded(
			_reference: GDSQLResourceReference,
	) -> GDSQLOperationResult:
		requests += 1
		var result := GDSQLOperationResult.new()
		result.value = true
		return result


	func poll_threaded(
			_reference: GDSQLResourceReference,
	) -> GDSQLOperationResult:
		polls += 1
		var result := GDSQLOperationResult.new()
		result.value = (
			GDSQLResourceLoadProgress.in_progress(0.5)
			if polls == 1
			else GDSQLResourceLoadProgress.loaded(resolved_resource)
		)
		return result


class ScopeResolver:
	extends GDSQLResourceResolver

	var resolved_resource: Resource
	var requests := 0
	var polls: Dictionary[String, int] = { }
	var failing_path := ""


	func _init(resource: Resource, failure: String = "") -> void:
		resolved_resource = resource
		failing_path = failure


	func resolve(_reference: GDSQLResourceReference) -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.value = resolved_resource
		return result


	func request_threaded(reference: GDSQLResourceReference) -> GDSQLOperationResult:
		requests += 1
		var result := GDSQLOperationResult.new()
		if reference.fallback_path == failing_path:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_TEST_PREFETCH_FAILED",
					"Forced prefetch request failure.",
				),
			)
			return result
		result.value = true
		return result


	func poll_threaded(reference: GDSQLResourceReference) -> GDSQLOperationResult:
		var path := reference.fallback_path
		polls[path] = polls.get(path, 0) + 1
		var result := GDSQLOperationResult.new()
		result.value = GDSQLResourceLoadProgress.in_progress(0.25)
		if polls[path] >= 2:
			result.value = GDSQLResourceLoadProgress.loaded(resolved_resource)
		return result
func test_reference_decoding_does_not_materialize_the_asset() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := CountingResolver.new(icon)
	var codec := GDSQLGodotVariantCodec.new(resolver)
	var column := _referenced_column(icon)
	var encoded: Variant = codec.encode(icon, column)

	var reference := codec.decode_reference(encoded)

	assert_object(reference).is_not_null()
	assert_str(reference.fallback_path).is_equal(REFERENCED_ICON_PATH)
	assert_int(resolver.calls).is_zero()


func test_compatibility_decoding_materializes_through_injected_resolver() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := CountingResolver.new(icon)
	var codec := GDSQLGodotVariantCodec.new(resolver)
	var column := _referenced_column(icon)
	var encoded: Variant = codec.encode(icon, column)

	var decoded: Variant = codec.decode(encoded, column)

	assert_object(decoded).is_same(icon)
	assert_int(resolver.calls).is_equal(1)


func test_missing_reference_returns_a_structured_diagnostic() -> void:
	var reference := GDSQLResourceReference.new()
	reference.fallback_path = "res://missing/gdsql-resource-stage-a.tres"

	var result := GDSQLGodotResourceResolver.new().resolve(reference)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)) \
			.is_equal("GDSQL_RESOURCE_REFERENCE_MISSING")
	assert_object(result.diagnostics.entries[0].related_object).is_same(reference)


func test_deferred_handle_resolves_only_on_demand_and_reuses_loaded_value() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := CountingResolver.new(icon)
	var reference := GDSQLResourceReference.from_resource(
		icon,
		GDSQLResourceTypeConstraint.from_resource(icon),
	)
	var handle := reference.create_handle(resolver)

	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)
	assert_int(resolver.calls).is_zero()
	assert_object(handle.load().get_value()).is_same(icon)
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.LOADED)
	assert_float(handle.get_progress()).is_equal(1.0)
	assert_object(handle.load().get_value()).is_same(icon)
	assert_int(resolver.calls).is_equal(1)

	handle.release()

	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)
	assert_object(handle.get_resource()).is_null()
	assert_object(handle.load().get_value()).is_same(icon)
	assert_int(resolver.calls).is_equal(2)


func test_deferred_handle_reports_threaded_progress_and_completion() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := ThreadedResolver.new(icon)
	var reference := GDSQLResourceReference.from_resource(
		icon,
		GDSQLResourceTypeConstraint.from_resource(icon),
	)
	var handle := reference.create_handle(resolver)
	var completed: Array[Resource] = []
	handle.load_completed.connect(func(resource: Resource) -> void: completed.append(resource))

	var requested := handle.request_load()

	assert_bool(requested.is_successful()).is_true()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.LOADING)
	assert_int(resolver.requests).is_equal(1)
	var synchronous := handle.load()
	assert_bool(synchronous.is_successful()).is_false()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.LOADING)
	var first_poll := handle.poll_load()
	assert_bool(first_poll.is_successful()).is_true()
	assert_float(handle.get_progress()).is_equal(0.5)
	assert_bool((first_poll.get_value() as GDSQLResourceLoadProgress).is_complete()) \
			.is_false()
	var completed_poll := handle.poll_load()

	assert_bool(completed_poll.is_successful()).is_true()
	assert_bool((completed_poll.get_value() as GDSQLResourceLoadProgress).is_complete()) \
			.is_true()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.LOADED)
	assert_object(handle.get_resource()).is_same(icon)
	assert_array(completed).contains_exactly([icon])


func test_deferred_handle_reports_unsupported_threaded_resolver() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var reference := GDSQLResourceReference.from_resource(
		icon,
		GDSQLResourceTypeConstraint.from_resource(icon),
	)
	var handle := reference.create_handle(CountingResolver.new(icon))

	var result := handle.request_load()

	assert_bool(result.is_successful()).is_false()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.FAILED)
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RESOURCE_THREADED_UNSUPPORTED",
	)


func test_deferred_handle_retains_failure_diagnostics() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var reference := GDSQLResourceReference.from_resource(
		icon,
		GDSQLResourceTypeConstraint.from_resource(icon),
	)
	var handle := reference.create_handle(FailingResolver.new())

	var result := handle.load()

	assert_bool(result.is_successful()).is_false()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.FAILED)
	assert_str(String(handle.get_diagnostics()[0].code)).is_equal(
		"GDSQL_TEST_RESOURCE_FAILED",
	)


func test_deferred_handle_rejects_a_mismatched_resource_type() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var reference := GDSQLResourceReference.from_resource(
		icon,
		GDSQLResourceTypeConstraint.from_resource(icon),
	)
	var handle := reference.create_handle(CountingResolver.new(Resource.new()))

	var result := handle.load()

	assert_bool(result.is_successful()).is_false()
	assert_int(handle.get_status()).is_equal(GDSQLResourceHandle.Status.FAILED)
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RESOURCE_HANDLE_TYPE_MISMATCH",
	)


func test_prefetch_scope_reports_aggregate_progress_and_releases_handles() -> void:
	var resource := Resource.new()
	var resolver := ScopeResolver.new(resource)
	var first := _fake_reference("res://prefetch/first.tres").create_handle(resolver)
	var second := _fake_reference("res://prefetch/second.tres").create_handle(resolver)
	var scope := GDSQLResourcePrefetchScope.from_handles([first, second])
	var completed_count := [0]
	scope.completed.connect(func(_resources: Array[Resource]) -> void: completed_count[0] += 1)

	var requested := scope.request_load()
	var first_poll := scope.poll_load()
	var first_progress := first_poll.get_value() as GDSQLResourcePrefetchProgress
	var completed_poll := scope.poll_load()
	var completed_progress := completed_poll.get_value() as GDSQLResourcePrefetchProgress

	assert_bool(requested.is_successful()).is_true()
	assert_int(scope.get_status()).is_equal(GDSQLResourcePrefetchScope.Status.LOADED)
	assert_float(first_progress.progress).is_equal(0.25)
	assert_bool(completed_progress.is_successful()).is_true()
	assert_int(completed_progress.loaded_count).is_equal(2)
	assert_int(completed_count[0]).is_equal(1)
	assert_int(resolver.requests).is_equal(2)
	scope.release()
	assert_int(scope.get_status()).is_equal(GDSQLResourcePrefetchScope.Status.READY)
	assert_int(first.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)
	assert_int(second.get_status()).is_equal(GDSQLResourceHandle.Status.UNLOADED)


func test_prefetch_scope_finishes_remaining_handles_after_one_request_fails() -> void:
	var resource := Resource.new()
	var failed_path := "res://prefetch/missing.tres"
	var resolver := ScopeResolver.new(resource, failed_path)
	var available := _fake_reference("res://prefetch/available.tres").create_handle(resolver)
	var missing := _fake_reference(failed_path).create_handle(resolver)
	var scope := GDSQLResourcePrefetchScope.from_handles([available, missing])

	var requested := scope.request_load()
	scope.poll_load()
	var completed := scope.poll_load()
	var progress := completed.get_value() as GDSQLResourcePrefetchProgress

	assert_bool(requested.is_successful()).is_false()
	assert_int(scope.get_status()).is_equal(GDSQLResourcePrefetchScope.Status.FAILED)
	assert_bool(progress.is_complete()).is_true()
	assert_int(progress.loaded_count).is_equal(1)
	assert_int(progress.failed_count).is_equal(1)
	assert_str(String(scope.get_diagnostics()[0].code)).is_equal(
		"GDSQL_TEST_PREFETCH_FAILED",
	)


func _referenced_column(prototype: Resource) -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	column.resource_type = GDSQLResourceTypeConstraint.from_resource(prototype)
	column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	return column


func _fake_reference(path: String) -> GDSQLResourceReference:
	var reference := GDSQLResourceReference.new()
	reference.fallback_path = path
	reference.expected_type = &"Resource"
	return reference
