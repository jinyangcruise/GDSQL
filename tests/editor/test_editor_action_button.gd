class_name GDSQLEditorActionButtonTest
extends GdUnitTestSuite


func test_scene_authored_presentation_takes_precedence() -> void:
	var button := auto_free(GDSQLEditorActionButton.new()) \
			as GDSQLEditorActionButton
	var authored_icon := ImageTexture.new()
	button.text = "Apply"
	button.tooltip_text = "Apply this draft"
	button.icon = authored_icon
	button.flat = false

	button.configure(
		_create_hub(),
		GDSQLEditorActionDefinition.new(
			&"test.apply",
			"Action Label",
			"Action tooltip",
			&"Add",
		),
	)

	assert_str(button.text).is_equal("Apply")
	assert_str(button.tooltip_text).is_equal("Apply this draft")
	assert_object(button.icon).is_same(authored_icon)
	assert_bool(button.flat).is_false()


func test_action_presentation_fills_empty_button_fields() -> void:
	var button := auto_free(GDSQLEditorActionButton.new()) \
			as GDSQLEditorActionButton
	button.configure(
		_create_hub(),
		GDSQLEditorActionDefinition.new(
			&"test.apply",
			"Action Label",
			"Action tooltip",
		),
	)

	assert_str(button.text).is_equal("Action Label")
	assert_str(button.tooltip_text).is_equal("Action tooltip")


func _create_hub() -> GDSQLEditorActionHub:
	var hub := GDSQLEditorActionHub.new()
	var context := GDSQLContextActionHub.new(GDSQLEditorActionHub.GLOBAL_CONTEXT)
	hub.register_context(context)
	context.add_action(
		GDSQLEditorActionDefinition.new(&"test.apply", "Action Label"),
		func() -> GDSQLOperationResult:
			return GDSQLOperationResult.new(),
	)
	return hub
