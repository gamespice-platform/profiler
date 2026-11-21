@tool
extends EditorPlugin

## Editor entry point for GameSpice Profiler. No autoloads: a game places one GSProfiler where it wants one.


func _enter_tree() -> void:
	add_custom_type("GSProfiler", "Node", load("res://addons/dot_profiler/runtime/dot_profiler.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("GSProfiler")
