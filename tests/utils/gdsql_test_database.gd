class_name GDSQLTestDatabase
extends RefCounted

const DEFAULT_DATABASE_NAME := &"game_config"
const HEROES_TABLE_NAME := &"heroes"


static func create_heroes_database(
		data_root: String,
		include_level: bool = false,
) -> GDSQLDatabase:
	var table := GDSQLTableDefinition.new(HEROES_TABLE_NAME, &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	if include_level:
		table.add_column(GDSQLColumnDefinition.new(&"level", TYPE_INT, false))
	return create_database(data_root, table)


static func create_database(
		data_root: String,
		table: GDSQLTableDefinition,
		database_name: StringName = DEFAULT_DATABASE_NAME,
) -> GDSQLDatabase:
	var database_result := GDSQLDatabase.create(database_name, data_root)
	assert(database_result.is_successful(), "Test database creation failed.")
	var database := database_result.get_database()
	var table_result := database.create_table(table)
	assert(table_result.is_successful(), "Test table creation failed.")
	return database


static func insert_rows(
		database: GDSQLDatabase,
		rows: Array[Dictionary],
		table_name: StringName = HEROES_TABLE_NAME,
) -> void:
	for row in rows:
		var result := database.insert(table_name, row)
		assert(result.is_successful(), "Test row insertion failed.")


static func insert_basic_heroes(database: GDSQLDatabase) -> void:
	insert_rows(
		database,
		[
			{&"id": 1, &"name": "Knight"},
			{&"id": 2, &"name": "Mage"},
		],
	)


static func insert_named_heroes(
		database: GDSQLDatabase,
		names: Array[String],
) -> void:
	var rows: Array[Dictionary] = []
	for index in names.size():
		rows.append({&"id": index + 1, &"name": names[index]})
	insert_rows(database, rows)


static func id_equals(id: int) -> GDSQLComparisonExpression:
	return GDSQLComparisonExpression.new(
		GDSQLColumnExpression.new(&"id"),
		GDSQLComparisonExpression.ComparisonOperator.EQUAL,
		GDSQLLiteralExpression.new(id),
	)
