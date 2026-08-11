class_name GDSQLEditorActionHubTest
extends GdUnitTestSuite


func test_invoke_can_request_the_main_screen() -> void:
	var hub := GDSQLEditorActionHub.new()
	var context := GDSQLContextActionHub.new(GDSQLEditorActionHub.GLOBAL_CONTEXT)
	assert_bool(hub.register_context(context).is_successful()).is_true()
	assert_bool(
		context.add_action(
			GDSQLEditorActionDefinition.new(&"test.open", "Open"),
			func() -> GDSQLOperationResult:
				return GDSQLOperationResult.new(),
		).is_successful(),
	).is_true()
	var requests: Array[bool] = []
	hub.main_screen_requested.connect(func() -> void: requests.append(true))

	hub.invoke(&"test.open")
	assert_int(requests.size()).is_zero()
	hub.invoke(&"test.open", [], true)
	assert_int(requests.size()).is_equal(1)
