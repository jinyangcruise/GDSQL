@icon("res://addons/gdsql/gbatis/img/GBMapperGraph.svg")
class_name GDMapperGraph
extends Resource

var config: ConfigFile


func load(path: String):
	config = ConfigFile.new()
	config.load(path)
