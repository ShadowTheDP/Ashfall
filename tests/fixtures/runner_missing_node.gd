extends SceneTree
## Negative fixture: Godot reports an engine error while still exiting with 0.

func _initialize() -> void:
	root.get_node("RunnerMissingNode")
	quit(0)
