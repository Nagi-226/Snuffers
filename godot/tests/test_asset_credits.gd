extends SceneTree

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate() as Control
	root.add_child(title)
	await process_frame
	var button := title.get_node_or_null("CreditsButton") as Button
	var panel := title.get_node_or_null("CreditsPanel") as Control
	_assert(button != null and panel != null, "title screen has an asset credits entry and panel")
	if button == null or panel == null:
		title.queue_free()
		_finish()
		return
	_assert(not panel.visible, "asset credits are initially closed")
	button.pressed.emit()
	_assert(panel.visible and not title._started, "opening credits keeps the title screen active")
	var text := panel.get_node("VBox/CreditsText") as RichTextLabel
	for author in ["michalstk11", "Sambit_Raut", "elitej1gaming", "D_U", "mbvisuals1", "8sianDude", "user77", "DJMaesen", "3dvachevsky"]:
		_assert(author in text.text, "credits include the source author " + author)
	_assert("CC-BY 4.0" in text.text and "https://creativecommons.org/licenses/by/4.0/" in text.text, "credits identify the license and its URL")
	_assert("https://sketchfab.com/" in text.text and "调整" in text.text, "credits include source URLs and the modification notice")
	var pressed := InputEventKey.new()
	pressed.keycode = KEY_SPACE
	pressed.pressed = true
	title._unhandled_input(pressed)
	_assert(panel.visible and not title._started, "keys inside credits cannot start gameplay")
	pressed.keycode = KEY_ESCAPE
	title._unhandled_input(pressed)
	_assert(not panel.visible and not title._started, "Escape closes credits without starting gameplay")
	button.pressed.emit()
	(panel.get_node("VBox/CloseButton") as Button).pressed.emit()
	_assert(not panel.visible and not title._started, "the close button returns to the title")
	var child_count := title.get_child_count()
	for iteration in 5:
		button.pressed.emit()
		(panel.get_node("VBox/CloseButton") as Button).pressed.emit()
	_assert(title.get_child_count() == child_count, "repeated open and close reuses the credits panel")
	title.queue_free()
	await process_frame
	_finish()


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("ASSET_CREDITS assertions=", _assertions, " failures=", _failures)
	quit(1 if _failures > 0 else 0)
