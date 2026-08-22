extends HBoxContainer
class_name SpinSlider
## Slider and spinbox over one value, kept in sync. Every panel in this editor
## re-implements this pair by hand (radius, strength, falloff, tolerance);
## this is the one copy.

signal value_changed(value: float)

## Backed by the spinbox, so there is exactly one copy of the number.
var value: float:
	get:
		return _spin.value if _spin != null else 0.0
	set(v):
		set_value_silent(v)

var _slider: HSlider
var _spin: SpinBox
var _syncing: bool = false


static func make(min_value: float, max_value: float, step: float,
		start: float = 0.0, suffix: String = "",
		rounded: bool = false) -> SpinSlider:
	var ctl := SpinSlider.new()
	ctl.configure(min_value, max_value, step, rounded)
	ctl.set_suffix(suffix)
	ctl.set_value_silent(start)
	return ctl


## Unbounded fields (a seed, a free-form count) get the spinbox only: a slider
## across a billion is a lie about what the user can aim at.
static func make_unbounded(step: float = 1.0, start: float = 0.0,
		suffix: String = "", rounded: bool = true) -> SpinSlider:
	var ctl := SpinSlider.new()
	ctl.configure(-PropertySchema.UNBOUNDED, PropertySchema.UNBOUNDED,
		step, rounded)
	ctl.set_slider_visible(false)
	ctl.set_suffix(suffix)
	ctl.set_value_silent(start)
	return ctl


func _init() -> void:
	name = "SpinSlider"
	add_theme_constant_override("separation", 6)
	_slider = HSlider.new()
	_slider.name = "Slider"
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.custom_minimum_size = Vector2(60, 0)
	add_child(_slider)
	_spin = SpinBox.new()
	_spin.name = "Spin"
	_spin.custom_minimum_size = Vector2(88, 0)
	_spin.select_all_on_focus = true
	add_child(_spin)
	_slider.value_changed.connect(_on_slider)
	_spin.value_changed.connect(_on_spin)


func configure(min_value: float, max_value: float, step: float,
		rounded: bool = false) -> void:
	for r: Range in [_slider, _spin]:
		r.min_value = min_value
		r.max_value = max_value
		r.step = step
		r.rounded = rounded
	_spin.allow_greater = false
	_spin.allow_lesser = false


func set_suffix(suffix: String) -> void:
	_spin.suffix = suffix


func set_slider_visible(on: bool) -> void:
	_slider.visible = on
	# With no slider the spinbox is the whole control, so let it take the room.
	_spin.size_flags_horizontal = Control.SIZE_SHRINK_END if on \
		else Control.SIZE_EXPAND_FILL


## Write without emitting. Scripted syncs must not read back as user edits.
func set_value_silent(v: float) -> void:
	_syncing = true
	_slider.value = v
	_spin.value = _slider.value
	_syncing = false


func get_value() -> float:
	return _spin.value


func slider() -> HSlider:
	return _slider


func spin_box() -> SpinBox:
	return _spin


func _on_slider(v: float) -> void:
	if _syncing:
		return
	_syncing = true
	_spin.value = v
	_syncing = false
	value_changed.emit(_spin.value)


func _on_spin(v: float) -> void:
	if _syncing:
		return
	_syncing = true
	_slider.value = v
	_syncing = false
	value_changed.emit(_spin.value)
