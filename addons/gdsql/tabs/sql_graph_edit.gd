@tool
extends GraphEdit

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

func _can_drop_data(_position, data):
	# { "type": "files", "files": ["res://src/dao/t_hero.gdmappergraph"], "from": @Tree@6840:<Tree#603409380691> }
	if data is Dictionary:
		if data.has("type") and data.has("files") and data.get("type") == "files":
			for i in data.get("files"):
				if i is String:
					if i.ends_with(".gdmappergraph"):
						return true
	return false
	
func _drop_data(_position, data):
	for i in data.get("files"):
		if i is String and i.ends_with(".gdmappergraph"):
			mgr.open_mapper_graph_file_tab.emit(i)
	
