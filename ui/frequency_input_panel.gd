class_name FrequencyInputPanel
extends CanvasLayer

signal ui_submitted_frequency_code(code: String)

const REQUIRED_DIGITS: int = 4

@export var input_action: StringName = &"frequency_input"

var _entry: LineEdit = null


func _ready() -> void:
	_entry = get_node_or_null("Root/FrequencyEntry") as LineEdit
	visible = false
	if _entry == null:
		return
	_entry.max_length = REQUIRED_DIGITS
	_entry.context_menu_enabled = false
	_entry.virtual_keyboard_enabled = false
	_entry.text_submitted.connect(_on_entry_text_submitted)


func open_panel() -> void:
	visible = true
	if _entry != null:
		_entry.text = ""
		_entry.grab_focus()


func close_panel() -> void:
	visible = false
	if _entry != null:
		_entry.release_focus()


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func submit_current_code() -> void:
	if _entry == null:
		return
	_submit_code(_entry.text)


func debug_submit_code(code: String) -> void:
	_submit_code(code)


func _on_entry_text_submitted(text: String) -> void:
	_submit_code(text)


func _submit_code(raw_code: String) -> void:
	var code: String = _digits_only(raw_code)
	if code.length() != REQUIRED_DIGITS:
		return
	ui_submitted_frequency_code.emit(code)
	close_panel()


func _digits_only(raw_code: String) -> String:
	var digits: String = ""
	for index: int in range(raw_code.length()):
		var character: String = raw_code.substr(index, 1)
		if character >= "0" and character <= "9":
			digits += character
	return digits
