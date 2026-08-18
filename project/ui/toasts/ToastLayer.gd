extends VBoxContainer
class_name ToastLayer
## Top-right toast stack. Click dismisses. Fade after ToastQueue.LIFETIME_S.

var _queue := ToastQueue.new()
var _cards: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	set_process(false)


func push(text: String, level: String = "") -> Dictionary:
	var now := _now_s()
	var item := _queue.push(text, level, now)
	_rebuild()
	set_process(true)
	return item


func dismiss(id: int) -> void:
	if _queue.dismiss(id):
		_rebuild()
	if _queue.items.is_empty():
		set_process(false)


func visible_count() -> int:
	return _queue.items.size()


func _process(_delta: float) -> void:
	var now := _now_s()
	var gone := _queue.expire(now)
	if not gone.is_empty():
		_rebuild()
	else:
		_update_fade(now)
	if _queue.items.is_empty():
		set_process(false)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	for item in _queue.items:
		var card := _make_card(item)
		_cards[int(item.get("id", 0))] = card
		add_child(card)
	_update_fade(_now_s())


func _make_card(item: Dictionary) -> PanelContainer:
	var id := int(item.get("id", 0))
	var level := str(item.get("level", LogRouter.LEVEL_INFO))
	var card := PanelContainer.new()
	card.name = "Toast_%d" % id
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = Vector2(260, 0)
	var accent := Color(0.62, 0.62, 0.66)
	if level == LogRouter.LEVEL_ERROR:
		accent = Color(0.95, 0.35, 0.32)
	elif level == LogRouter.LEVEL_WARNING:
		accent = Color(0.88, 0.64, 0.22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.12, 0.94)
	sb.border_color = accent
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.name = "Text"
	label.text = str(item.get("text", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94) if level != LogRouter.LEVEL_ERROR else Color(1.0, 0.72, 0.70))
	card.add_child(label)
	card.gui_input.connect(_on_card_input.bind(id))
	card.tooltip_text = "Click to dismiss"
	return card


func _on_card_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			dismiss(id)


func _update_fade(now: float) -> void:
	for item in _queue.items:
		var id := int(item.get("id", 0))
		var card: Control = _cards.get(id) as Control
		if card == null:
			continue
		var a := _queue.alpha_at(item, now)
		card.modulate = Color(1, 1, 1, a)


func _now_s() -> float:
	return float(Time.get_ticks_msec()) * 0.001
