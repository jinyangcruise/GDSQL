@icon("res://addons/gdsql/img/sql_file.svg")
class_name GDSQLText
extends Resource

var config: ConfigFile


func load(path: String):
	config = ConfigFile.new()
	config.load(path)
