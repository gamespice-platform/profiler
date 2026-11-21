@tool
extends EditorPlugin

## Editor entry point for GameSpice Profiler. No autoloads: a game places one GSProfiler where it wants one.


func _enter_tree() -> void:
	add_custom_type("GSProfiler", "Node", load("res://addons/gs_profiler/runtime/gs_profiler.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("GSProfiler")
