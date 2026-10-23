extends SceneTree
func _init():
	var d = LevelGen.generate(4, 20260214)
	var room = d["rooms"][0]
	print("keys=", room.keys())
	var p = room["platforms"]
	print("type=", typeof(p), " size=", p.size())
	var e = p[0]
	print("e type=", typeof(e), " e=", e)
	if e is Dictionary:
		print("  dict keys=", e.keys())
	quit()
