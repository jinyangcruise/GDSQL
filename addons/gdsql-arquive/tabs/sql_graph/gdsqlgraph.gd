@icon("res://addons/gdsql/img/GDSQLGraph.svg")
class_name GDSQLGraph
extends Resource

var config: ConfigFile


func load(path: String):
	config = ConfigFile.new()
	config.load(path)
