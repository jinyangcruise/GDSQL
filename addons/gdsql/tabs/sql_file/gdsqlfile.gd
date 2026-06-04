@icon("res://addons/gdsql/img/sql_file.svg")
extends Resource
class_name GDSQLText

var config: ConfigFile

func load(path: String):
	config = ConfigFile.new()
	config.load(path)
