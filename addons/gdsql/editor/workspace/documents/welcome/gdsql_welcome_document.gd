@tool
extends CenterContainer
## Landing document shown when no database task is active.

@onready var _create_database_button: GDSQLEditorActionButton = %CreateDatabase


func configure_actions(action_hub: GDSQLEditorActionHub) -> void:
	_create_database_button.configure_action(action_hub, GDSQLEditorActionIds.CREATE_DATABASE)
