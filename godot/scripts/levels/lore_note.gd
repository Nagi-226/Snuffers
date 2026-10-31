extends Node3D

@export var title := ""
@export_multiline var body := ""
@export var prompt := "E  阅读"


func interact() -> void:
	Events.message_posted.emit("%s\n%s" % [title, body])


func interact_prompt() -> String:
	return prompt
