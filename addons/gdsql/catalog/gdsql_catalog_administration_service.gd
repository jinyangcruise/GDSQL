@abstract
class_name GDSQLCatalogAdministrationService
extends RefCounted

@abstract
func create_database(database_name: StringName) -> GDSQLCatalogOperationResult


@abstract
func rename_database(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult


@abstract
func drop_database(database_name: StringName) -> GDSQLCatalogOperationResult


@abstract
func create_table(
		database_name: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLCatalogOperationResult


@abstract
func rename_table(
		database_name: StringName,
		current_name: StringName,
		new_name: StringName,
) -> GDSQLCatalogOperationResult


@abstract
func drop_table(
		database_name: StringName,
		table_name: StringName,
) -> GDSQLCatalogOperationResult


@abstract
func alter_table(
		database_name: StringName,
		table_name: StringName,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLCatalogOperationResult
