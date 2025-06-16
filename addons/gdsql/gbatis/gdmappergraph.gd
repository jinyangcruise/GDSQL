@icon("res://addons/gdsql/gbatis/img/GBMapperGraph.png")
extends Resource
class_name GDMapperGraph

var config: ConfigFile

func load(path: String):
	config = ConfigFile.new()
	config.load(path)
