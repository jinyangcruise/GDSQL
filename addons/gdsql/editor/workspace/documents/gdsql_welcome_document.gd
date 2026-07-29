@tool
extends CenterContainer
## Landing document shown when no database task is active.


func configure_actions(action_hub: GDSQLEditorActionHub) -> void:
	$WelcomePanel/WelcomeMargin/Content/CreateDatabase.configure_action(
		action_hub,
		GDSQLEditorActionIds.CREATE_DATABASE,
	)
